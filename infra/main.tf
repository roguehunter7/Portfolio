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

  # VM Startup Script: installs Docker Compose v2, clones the repo, and bootstraps
  # the Compose stack on first boot using the injected Cloudflare tunnel token.
  metadata_startup_script = replace(<<-EOF
    #!/bin/bash
    set -e

    # 1. Install Docker (CE) with Compose v2 plugin, Git, and Curl
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin git
    systemctl enable --now docker

    # 2. Clone the public portfolio repository
    rm -rf /opt/portfolio
    git clone https://github.com/roguehunter7/portfolio.git /opt/portfolio

    # 3. Clean line endings and ensure scripts are executable
    find /opt/portfolio -name "*.sh" -exec sed -i 's/\r$//' {} +
    chmod +x /opt/portfolio/*.sh

    # 4. Bootstrap Compose stack on first boot using the Terraform-supplied token.
    # Subsequent deployments are handled by GitHub Actions via deploy.sh.
    cd /opt/portfolio
    echo "IMAGE_TAG=latest" > .env
    echo "CLOUDFLARE_TUNNEL_TOKEN=${var.cloudflare_tunnel_token}" >> .env
    docker compose pull web 2>/dev/null || true
    docker compose up -d
    touch /var/log/startup_script_complete
  EOF
  , "\r", "")

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-13"
      type  = "pd-standard"
      size  = 20
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
