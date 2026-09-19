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

# Hermes' environment file, built here (not in the template) so the secrets are
# written to a 0600 file verbatim — no shell quoting, no interpolation inside
# the rendered cloud-init. Optional entries are dropped when empty.
#
# The dashboard is a systemd unit bound to 0.0.0.0 inside the box, so Hermes
# engages its auth gate and refuses to start without a provider: the
# username/password pair below is mandatory, and Access sits in front of it.
locals {
  hermes_env = join("\n", compact([
    "DEEPSEEK_API_KEY=${var.deepseek_api_key}",
    "TELEGRAM_BOT_TOKEN=${var.telegram_bot_token}",
    var.telegram_allowed_users != "" ? "TELEGRAM_ALLOWED_USERS=${var.telegram_allowed_users}" : "",
    "HERMES_DASHBOARD_BASIC_AUTH_USERNAME=admin",
    "HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=${var.hermes_dashboard_password}",
    "HERMES_DASHBOARD_BASIC_AUTH_SECRET=${var.hermes_dashboard_secret}",
  ]))
}

# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------

# ap-hyderabad-1 has a single availability domain; take the first.
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

# Latest Canonical Ubuntu 24.04 image for the A1.Flex (aarch64) shape.
# Ubuntu is a first-class OCI platform image with an `ubuntu` default user and
# the apt/ufw tooling the provisioning scripts expect. Hermes is installed
# natively as a dedicated `hermes` user: its installer brings uv-managed Python
# and its own Node, so the distro's Python/Node are never in the dependency path.
data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

# Tenancy-wide Object Storage namespace; bucket names are scoped by it.
data "oci_objectstorage_namespace" "this" {
  compartment_id = var.tenancy_ocid
}

# ---------------------------------------------------------------------------
# Network — the instance has a public IP for EGRESS only. There is no security
# group; ingress is denied by the host's ufw, and the only listeners are
# loopback-bound (sshd) or loopback-bound behind the cloudflared tunnel.
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

# ---------------------------------------------------------------------------
# Hermes state backups — the rebuild path reads from here.
# ---------------------------------------------------------------------------

# Dedicated private bucket for the state snapshots. Tiny (a few MB each) and
# inside the Always Free object-storage allowance shared with the tfstate bucket.
resource "oci_objectstorage_bucket" "hermes_backups" {
  compartment_id = var.tenancy_ocid
  namespace      = data.oci_objectstorage_namespace.this.namespace
  name           = "hermes-backups"
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"
}

# The box authenticates as itself (instance principal), so no API key ever lives
# on it. Matching on the compartment is deliberate: a rule pinned to
# instance.id would stop matching the moment the instance is rebuilt.
# ponytail: compartment-wide match. Any instance added to this tenancy inherits
# this policy. Switch to a tag.hermes.backup matching rule if a second instance
# ever lands here.
resource "oci_identity_dynamic_group" "hermes_backup" {
  compartment_id = var.tenancy_ocid
  name           = "hermes-backup"
  description    = "The Hermes dev box, for keyless object-storage state backups"
  matching_rule  = "All {instance.compartment.id = '${var.tenancy_ocid}'}"
}

resource "oci_identity_policy" "hermes_backup" {
  compartment_id = var.tenancy_ocid
  name           = "hermes-backup"
  description    = "Allow the Hermes dev box to manage only its own snapshot bucket"

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.hermes_backup.name} to read buckets in tenancy where target.bucket.name='hermes-backups'",
    "Allow dynamic-group ${oci_identity_dynamic_group.hermes_backup.name} to manage objects in tenancy where target.bucket.name='hermes-backups'",
  ]
}

# ---------------------------------------------------------------------------
# Compute — Always Free A1.Flex: 2 OCPU / 12 GB (June-2026 limits).
# cloud-init brings up sshd (loopback), cloudflared, the native Hermes install
# and the backup cron. The instance also holds the Always Free budget/quota
# guardrails' target resources.
# ---------------------------------------------------------------------------

resource "oci_core_instance" "portfolio_node" {
  compartment_id      = var.tenancy_ocid
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  shape               = "VM.Standard.A1.Flex"
  display_name        = "portfolio-node"

  # The cost-guard quota zeroes compute families then re-allows A1; the
  # instance must NOT launch until the quota update lands (race: it would hit
  # the still-zeroed regional limits). The backup policy must exist first too,
  # so the very first backup works without a retry loop.
  depends_on = [
    oci_limits_quota.free_tier_guard,
    oci_objectstorage_bucket.hermes_backups,
    oci_identity_policy.hermes_backup,
  ]

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
    assign_public_ip = true # outbound-only; ufw denies inbound
    display_name     = "portfolio-node-vnic"
  }

  # File bodies are passed encoded and written with cloud-init's `encoding`
  # field, so YAML indentation can never corrupt them and the rendered scripts
  # never contain a secret.
  # OCI caps user data + metadata at 32,000 bytes: everything that carries shell
  # metacharacters uses `gz+b64` (base64gzip); the small secret files use plain
  # `b64` (gzip would cost more than it saves there).
  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", {
      tunnel_token_b64    = base64encode(var.cloudflare_tunnel_token)
      hermes_env_b64      = base64encode(local.hermes_env)
      hermes_config_gzb64 = base64gzip(file("${path.module}/../hermes/config.yaml"))
      provision_gzb64     = base64gzip(file("${path.module}/../../scripts/provision.sh"))
      maintenance_gzb64   = base64gzip(file("${path.module}/../../scripts/maintenance.sh"))
      backup_gzb64        = base64gzip(file("${path.module}/../../scripts/hermes-backup.sh"))
      restore_gzb64       = base64gzip(file("${path.module}/../../scripts/hermes-restore.sh"))
      oci_namespace       = data.oci_objectstorage_namespace.this.namespace
      backup_bucket       = oci_objectstorage_bucket.hermes_backups.name
      region              = var.region
    }))
  }

  preserve_boot_volume = false
}

# ---------------------------------------------------------------------------
# Cost guardrails — most-restrictive, tenancy-wide (the whole account).
# Budget: alert on ANY spend ($1 budget, $0.01 absolute actual+forecast).
# Quota: allow exactly the Always Free A1.Flex (2 OCPU / 12 GB) + 1 boot
# volume + the tfstate/backup buckets; deny every other resource. Even on PAYG
# this keeps the account at $0 while inside Always Free limits.
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
  description    = "Deny everything except the Always Free A1.Flex VM (2 OCPU/12 GB), its storage, and the object-storage buckets"
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
    # Object storage — free tier is 20 GB (21474836480 bytes); tfstate + snapshots.
    "set object-storage quota storage-bytes to 21474836480 in tenancy",
  ]
}
