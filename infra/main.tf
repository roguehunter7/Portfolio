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

# 4. Compute Instance (e2-micro is free tier eligible in us-central1)
resource "google_compute_instance" "vm_instance" {
  name         = "portfolio-zero-trust-node"
  machine_type = "e2-micro"
  zone         = "us-central1-a"

  # VM Startup Script: minimal Hermes host — memory stack (zram + swap),
  # unattended-upgrades, and native cloudflared tunnel. No Docker.
  metadata_startup_script = replace(<<-EOF
    #!/bin/bash
    set -e

    export DEBIAN_FRONTEND=noninteractive

    # 1. Base packages
    apt-get update -y
    apt-get install -y curl git ca-certificates zram-tools unattended-upgrades ripgrep ffmpeg

    # 2. Memory: 2 GB zram (compressed RAM swap) + 6 GB disk swapfile
    sed -i 's/^#\?ALGO=lz4/ALGO=zstd/; s/^#\?PERCENT=50/PERCENT=200/' /etc/default/zramswap
    systemctl enable --now zramswap
    if [ ! -f /swapfile ]; then
      fallocate -l 6G /swapfile
      chmod 600 /swapfile
      mkswap /swapfile
    fi
    swapon /swapfile || true
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    cat > /etc/sysctl.d/99-memory.conf <<'CONF'
    vm.swappiness=180
    vm.page-cluster=0
    CONF
    sysctl --system

    # 3. Unattended auto-updates (daily; auto-reboot 03:00 when needed)
    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'CONF'
    APT::Periodic::Update-Package-Lists "1";
    APT::Periodic::Unattended-Upgrade "1";
    APT::Periodic::AutocleanInterval "7";
    CONF
    sed -i 's|^//Unattended-Upgrade::Automatic-Reboot "false";|Unattended-Upgrade::Automatic-Reboot "true";|' /etc/apt/apt.conf.d/50unattended-upgrades

    # 4. Dedicated unprivileged user for Hermes
    id -u hermes >/dev/null 2>&1 || useradd -m -s /bin/bash hermes

    # 5. Native cloudflared (official deb) as a token-based systemd service
    curl -sL -o /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
    dpkg -i /tmp/cloudflared.deb || apt-get install -f -y
    cloudflared service install ${var.cloudflare_tunnel_token}
    systemctl enable --now cloudflared

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
      # Public IP for outbound internet access (git fetch, docker pull).
      # Ingress remains fully locked down by deny-all-ingress + IAP-only SSH.
    }
  }
}
