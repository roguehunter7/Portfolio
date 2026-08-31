terraform {
  backend "gcs" {
    bucket = "main-project-402906-tfstate"
    prefix = "terraform/state"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = "main-project-402906"
  region  = "us-central1"
}

# --- INFRASTRUCTURE ---

# 1. Custom Zero-Trust VPC Network
resource "google_compute_network" "zero_trust_vpc" {
  name                    = "zero-trust-vpc"
  auto_create_subnetworks = true
}

# 2. Deny-All Ingress Rule (Default VPC behavior explicitly defined)
resource "google_compute_firewall" "deny_all_ingress" {
  name    = "deny-all-ingress"
  network = google_compute_network.zero_trust_vpc.name

  deny {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# 3. Allow SSH Ingress ONLY from Google secure Identity-Aware Proxy (IAP)
resource "google_compute_firewall" "allow_iap_ssh" {
  name     = "allow-iap-ssh"
  network  = google_compute_network.zero_trust_vpc.name
  priority = 900
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Google secure IAP proxy IP range
  source_ranges = ["35.235.240.0/20"]
}

# 4. Least-privilege backup service account for the nightly Vaultwarden SQLite
#    backup (backup.sh fetches its metadata token for THIS SA — not the default
#    project editor, and not the CI/WIF SA). Scoped to a dedicated bucket only.
resource "google_service_account" "vaultwarden_backup" {
  account_id   = "vaultwarden-backup"
  display_name = "Vaultwarden backup SA"
  description  = "Least-privilege SA for the nightly vaultwarden SQLite object upload"
}

# Dedicated bucket so the backup SA can never touch the tfstate bucket.
# Regional (US-CENTRAL1) and tiny — stays inside the Always Free 5 GB/5k-ops allotment.
resource "google_storage_bucket" "vaultwarden_backups" {
  name                        = "main-project-402906-vaultwarden-backups"
  location                    = "US-CENTRAL1"
  force_destroy               = false
  uniform_bucket_level_access = true
}

# storage.objectUser on the dedicated bucket (no prefix condition — object
# listing is a bucket-level permission and would be denied by a prefix condition).
resource "google_storage_bucket_iam_member" "backup_object_user" {
  bucket = google_storage_bucket.vaultwarden_backups.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.vaultwarden_backup.email}"
}

# 5. Compute Instance (e2-micro is free tier eligible in us-central1)
# Fresh Vaultwarden host: single Rust container (127.0.0.1:8000) + cloudflared
# container behind the Cloudflare Tunnel. Zero ingress at the firewall; admin
# via IAP-SSH backdoor. The instance runs as the least-privilege backup SA with
# storage-only scope; the CI/WIF SA is used separately by the workflow.
resource "google_compute_instance" "vm_instance" {
  name         = "portfolio-zero-trust-node"
  machine_type = "e2-micro"
  zone         = "us-central1-a"

  service_account {
    email  = google_service_account.vaultwarden_backup.email
    scopes = ["https://www.googleapis.com/auth/devstorage.read_write"]
  }

  # VM Startup Script: host baseline only (Docker + Compose plugin). The
  # vaultwarden/cloudflared containers and their .env are written later by the
  # vaultwarden-setup workflow over IAP-SSH. Corrective maintenance (OS upgrade
  # + reboot + container auto-pull) runs from a cron on the 5th of each month.
  metadata_startup_script = replace(<<-EOF
    #!/bin/bash
    set -euo pipefail

    export DEBIAN_FRONTEND=noninteractive

    # 1. Host baseline: Docker Engine + Docker Compose v2 plugin (official repo).
    #    Vaultwarden and cloudflared run as containers; the host only needs a
    #    stable container runtime. Compose gives us `docker compose` for the cron.
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg git apt-transport-https python3   # python3 = backup.sh dep (no gcloud)
    # Official Docker repository (gives docker-ce + docker-compose-plugin reliably).
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # 2. Bring up Docker at boot.
    systemctl enable --now docker

    # 3. Compose project dir + backup script home for the vaultwarden/cloudflared
    #    stack. The compose file, .env, and backup.sh are written later by the
    #    vaultwarden-setup workflow over IAP-SSH. Backup uses the metadata
    #    service-account token directly (no google-cloud-cli needed).
    mkdir -p /opt/vaultwarden

    # 5. Maintenance cron:
    #    - Daily 03:00: run backup.sh — SQLite -> GCS via the metadata SA token,
    #      prune to the newest 5. Guarded on backup.sh existing so a pre-deploy
    #      morning cron is a clean no-op.
    #    - 5th of month 03:05: refresh container images, upgrade host OS, reboot.
    #    Written via printf (not a heredoc) so the crontab lines start at column 0.
    printf '%s\n' \
      'SHELL=/bin/bash' \
      'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin' \
      '0 3 * * * root test -f /opt/vaultwarden/backup.sh && bash /opt/vaultwarden/backup.sh' \
      '5 3 5 * * root cd /opt/vaultwarden 2>/dev/null && [ -f docker-compose.yml ] && docker compose pull --quiet && docker compose up -d ; DEBIAN_FRONTEND=noninteractive apt-get update -y && apt-get upgrade -y && shutdown -r now' \
      > /etc/cron.d/vaultwarden
    chmod 0644 /etc/cron.d/vaultwarden

    touch /var/log/startup_script_complete
  EOF
  , "\r", "")

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-13"
      type  = "pd-standard"
      size  = 25
    }
  }

  network_interface {
    network = google_compute_network.zero_trust_vpc.id
    access_config {
      # Public IP for outbound internet access (docker pull, apt, tunnel egress).
      # Ingress remains fully locked down by deny-all-ingress + IAP-only SSH.
    }
  }
}
