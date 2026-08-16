terraform {
  required_version = ">= 1.3"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.0"
    }
  }

  # State in OCI Object Storage (free tier). Bucket/namespace/key are injected
  # by CI via -backend-config; the bucket is created before `terraform init`.
  backend "oci" {}
}

provider "oci" {
  region = var.region
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------

# ap-hyderabad-1 has a single availability domain; take the first.
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Latest Canonical Ubuntu 24.04 image for the A1.Flex (ARM64) shape.
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# ---------------------------------------------------------------------------
# Network — zero ingress. The instance has a public IP for EGRESS only;
# the NSG has no rules at all (deny-all), so no port is reachable from the
# internet. SSH arrives via the cloudflared tunnel (outbound connection).
# ---------------------------------------------------------------------------

resource "oci_core_vcn" "zero_trust_vcn" {
  compartment_id = var.tenancy_ocid
  cidr_blocks    = ["10.0.0.0/16"]
  display_name   = "zero-trust-vcn"
  dns_label      = "zerotrust"
}

resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.zero_trust_vcn.id
  display_name   = "igw"
}

resource "oci_core_route_table" "public_rt" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.zero_trust_vcn.id
  display_name   = "public-rt"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}

resource "oci_core_subnet" "public" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.zero_trust_vcn.id
  cidr_block     = "10.0.0.0/24"
  display_name   = "public"
  dns_label      = "public"
  route_table_id = oci_core_route_table.public_rt.id
}

# Zero rules = deny all ingress. (No SSH rule: SSH goes through cloudflared.)
resource "oci_core_network_security_group" "instance_nsg" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_vcn.zero_trust_vcn.id
  display_name   = "instance-nsg"
}

# ---------------------------------------------------------------------------
# Compute — Always Free A1.Flex: 2 OCPU / 12 GB (June-2026 limits).
# cloud-init installs + runs cloudflared so SSH is reachable only via the
# existing Cloudflare tunnel (ssh.sreeramkr.com -> localhost:22).
# ---------------------------------------------------------------------------

resource "oci_core_instance" "portfolio_node" {
  compartment_id      = var.tenancy_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  shape               = "VM.Standard.A1.Flex"
  display_name        = "portfolio-node"

  # The cost-guard quota zeroes compute families then re-allows A1; the
  # instance must NOT launch until the quota update lands (race: it would hit
  # the still-zeroed regional limits).
  depends_on = [oci_limits_quota.free_tier_guard]

  shape_config {
    ocpus         = 2
    memory_in_gbs = 12
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = 50 # min size; counts toward the 200 GB Always Free block storage
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true # outbound-only; NSG has zero ingress rules
    nsg_ids          = [oci_core_network_security_group.instance_nsg.id]
    display_name     = "portfolio-node-vnic"
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
      cloudflare_tunnel_token = var.cloudflare_tunnel_token
      ttyd_password           = var.ttyd_password
    }))
  }

  preserve_boot_volume = false
}

# ---------------------------------------------------------------------------
# Cost guardrails — most-restrictive, tenancy-wide (the whole account).
# Budget: alert on ANY spend ($1 budget, $0.01 absolute actual+forecast).
# Quota: allow exactly the Always Free A1.Flex (2 OCPU / 12 GB) + 1 boot
# volume + tfstate bucket; deny every other resource. Even on PAYG this
# keeps the account at $0 while inside Always Free limits.
# ---------------------------------------------------------------------------

resource "oci_budget_budget" "free_tier_guard" {
  amount         = "1"
  compartment_id = var.tenancy_ocid
  reset_period   = "MONTHLY"
  target_type    = "COMPARTMENT"
  targets        = [var.tenancy_ocid] # root compartment == whole tenancy
  display_name   = "free-tier-guard"
  description    = "Most-restrictive guard: alert on any spend at all (free tier only)"
}

resource "oci_budget_alert_rule" "actual_spend" {
  budget_id      = oci_budget_budget.free_tier_guard.id
  threshold      = "0.01"
  threshold_type = "ABSOLUTE"
  type           = "ACTUAL"
  display_name   = "any-actual-spend"
  description    = "Triggers on any real spend (free tier should be $0)"
  message        = "OCI spend detected above $0.01 — check for a resource outside Always Free limits"
  recipients     = var.budget_alert_email
}

resource "oci_budget_alert_rule" "forecast_spend" {
  budget_id      = oci_budget_budget.free_tier_guard.id
  threshold      = "0.01"
  threshold_type = "ABSOLUTE"
  type           = "FORECAST"
  display_name   = "any-forecast-spend"
  description    = "Triggers if spend is forecast to exceed $0.01"
  message        = "OCI forecast spend above $0.01 — a paid resource is likely being created"
  recipients     = var.budget_alert_email
}

resource "oci_limits_quota" "free_tier_guard" {
  compartment_id = var.tenancy_ocid
  name           = "free-tier-guard"
  description    = "Deny everything except the Always Free A1.Flex VM (2 OCPU/12 GB), its storage, and the tfstate bucket"
  statements = [
    # Compute — zero ALL core/memory quotas, then re-allow exactly the Always
    # Free A1.Flex allowance (AD-scoped AND regional names). Nothing else
    # (E2/E3/E4, X9, GPU, dense-io, etc.) can ever be launched, on PAYG or not.
    "zero compute-core quotas in tenancy",
    "zero compute-memory quotas in tenancy",
    "set compute-core quota standard-a1-core-count to 2 in tenancy",
    "set compute-core quota standard-a1-core-regional-count to 2 in tenancy",
    "set compute-memory quota standard-a1-memory-count to 12 in tenancy",
    "set compute-memory quota standard-a1-memory-regional-count to 12 in tenancy",
    # Block storage — free tier is 200 GB total block+boot; no backups.
    "set block-storage quota total-storage-gb to 200 in tenancy",
    "set block-storage quota backup-count to 0 in tenancy",
    # Object storage — free tier is 20 GB (21474836480 bytes); tfstate bucket only.
    "set object-storage quota storage-bytes to 21474836480 in tenancy",
  ]
}
