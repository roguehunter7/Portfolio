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

# 3. The Compute Instance
resource "google_compute_instance" "vm_instance" {
  name         = "portfolio-zero-trust-node"
  machine_type = "e2-micro"
  zone         = "us-central1-a"

  # DevSecOps: Injecting the secret variable securely
  metadata_startup_script = replace(<<-EOF
    #!/bin/bash
    
    # 1. Update OS and install dependencies
    apt-get update -y
    apt-get install -y docker.io git curl

    # 2. Install Cloudflared
    mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list
    apt-get update -y
    apt-get install -y cloudflared

    # 3. Authenticate Cloudflared
    cloudflared service install ${var.cloudflare_tunnel_token}
    
    # 4. Clone GitHub Repo automatically using injected PAT
    git clone https://${var.github_pat}@github.com/roguehunter7/portfolio.git /opt/portfolio
    cd /opt/portfolio
    chmod +x setup.sh deploy.sh
    ./deploy.sh
    ./setup.sh
  EOF
  , "\r", "")

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2604-lts-amd64"
    }
  }

  network_interface {
    network = google_compute_network.zero_trust_vpc.id
    access_config {}
  }
}