terraform {
  backend "gcs" {
    bucket = "sreeram-terraform-state-bucket" # Use the exact name you created
    prefix = "terraform/state"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.8"
    }
  }
}

provider "google" {
  project = "main-project-402906"
  region  = "us-central1"
}

# --- VARIABLES ---
variable "cloudflare_tunnel_token" {
  description = "The Cloudflare Zero Trust Tunnel Token"
  type        = string
  sensitive   = true # This prevents Terraform from logging the token to the console
}

variable "github_pat" {
  description = "GitHub Personal Access Token for private repo clone"
  type        = string
  sensitive   = true
}

# --- INFRASTRUCTURE ---

# 1. The Custom Zero-Trust VPC
resource "google_compute_network" "zero_trust_vpc" {
  name                    = "zero-trust-vpc"
  auto_create_subnetworks = true
}

# 2. The Explicit Deny-All Firewall Rule
resource "google_compute_firewall" "deny_all_ingress" {
  name    = "deny-all-ingress"
  network = google_compute_network.zero_trust_vpc.name

  deny {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# Allow secure SSH access ONLY through Google Identity-Aware Proxy (IAP)
resource "google_compute_firewall" "allow_iap_ssh" {
  name    = "allow-iap-ssh"
  network = google_compute_network.zero_trust_vpc.name
  priority = 900
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # This IP range is owned exclusively by Google's secure IAP proxy [1]
  source_ranges = ["35.235.240.0/20"] 
}

# 3. The Compute Instance
resource "google_compute_instance" "vm_instance" {
  name         = "portfolio-zero-trust-node"
  machine_type = "e2-micro"
  zone         = "us-central1-a"

  # High-Performance Debian Startup Script
  metadata_startup_script = <<-EOF
    #!/bin/bash
    # 1. OS Preparation
    apt-get update -y
    apt-get install -y docker.io git curl
    systemctl enable --now docker

    # 2. Install Cloudflared
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main" | tee /etc/apt/sources.list.d/cloudflared.list
    apt-get update -y
    apt-get install -y cloudflared

    # 3. Authenticate Tunnel
    cloudflared service install ${var.cloudflare_tunnel_token}
    
    # 4. Clone Repo
    rm -rf /opt/portfolio
    git clone https://${var.github_pat}@github.com/roguehunter7/portfolio.git /opt/portfolio
    
    # 5. KILL THE WINDOWS GHOSTS IMMEDIATELY
    find /opt/portfolio -name "*.sh" -exec sed -i 's/\r$//' {} +
    chmod +x /opt/portfolio/*.sh

    # 6. Run Setup & Initial Deploy
    cd /opt/portfolio
    ./deploy.sh
  EOF

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = google_compute_network.zero_trust_vpc.id
    access_config {}
  }
}