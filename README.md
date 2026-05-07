# 🛡️ Zero-Trust Cloud Infrastructure & Native GitOps Pipeline

![GCP](https://img.shields.io/badge/Google_Cloud-4285F4?style=for-the-badge&logo=google-cloud&logoColor=white)
![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![Cloudflare](https://img.shields.io/badge/Cloudflare-F38020?style=for-the-badge&logo=Cloudflare&logoColor=white)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)

## 📌 Overview
This repository contains the **Infrastructure as Code (IaC)** and automation logic for a highly secure, self-healing, zero-ingress cloud architecture. 

Unlike traditional "ClickOps" setups, this entire environment—from VPC networking and firewall rules to the compute node and its internal GitOps pipeline—is defined in code, ensuring **idempotent deployments** and instant disaster recovery.

## 🏗️ Architecture Design

    [Public Internet] 
           │ (Strict HTTPS / DNSSEC / HSTS)
           ▼
    [Cloudflare Edge / WAF] ─── (Blocks AI Scrapers & Botnets)
           │
           │ (Encrypted Outbound Egress Tunnel)
           ▼
    [GCP VPC Firewall] ─── (ALL Inbound Ingress Rules DROPPED)
           │
    [GCP e2-micro Node] ◀─── [Terraform Provisioned] ◀─── [GCS Remote State]
           │
           ├─ [cloudflared daemon] ── (Bridges Tunnel to Localhost:80)
           ├─ [systemd.timer] ─── (Polls GitHub Native every 2 mins)
           └─ [Docker Engine] ─── (Runs hardened nginx:alpine)

## 🧠 Core Engineering Decisions

### 1. Infrastructure as Code (Terraform)
The environment is provisioned using **Terraform**. To enable cross-platform collaboration (e.g., switching between Windows and Linux development machines), I implemented a **Remote Backend using Google Cloud Storage (GCS)** with object versioning. This prevents state loss and ensures architectural consistency.

### 2. Zero Trust & Origin Masking
The origin server is 100% invisible to the public internet. By utilizing **Cloudflare Zero Trust Tunnels**, the GCP VPC firewall is configured to drop all inbound TCP traffic. Reconnaissance tools like Shodan or automated port scanners see no open ports, mitigating direct-to-IP DDoS and brute-force vectors.

### 3. Resource-Optimized "Native" GitOps
Running heavy CI/CD runners (Jenkins/GitHub Actions) on a 1GB RAM micro-instance is inefficient. I engineered a **Native GitOps poller** using Linux `systemd` and `bash`. It uses `git ls-remote` to detect SHA deltas with minimal CPU/RAM overhead, triggering automated Docker rebuilds only when changes are merged.

### 4. DevSecOps Image Hardening
To remediate upstream vulnerabilities in the `nginx:alpine` base image, the build process injects an automated OS-level package patch (`apk upgrade`) during the containerization phase.

## 📂 Repository Structure

* `main.tf` : Terraform configuration for VPC, Firewalls, and Compute.
* `main.html` : The frontend portfolio case study.
* `Dockerfile` : Nginx-Alpine configuration with integrated security patching.
* `deploy.sh` : The core CD logic. Uses native Git to poll SHAs and manage Docker lifecycles.
* `setup.sh` : Provisioning script that bootstraps the native Systemd GitOps timer.

## ⚙️ Automated Deployment Flow (`deploy.sh`)

1. **State Check:** Queries the remote origin natively via `git ls-remote` (using a secure PAT).
2. **Evaluation:** Compares remote SHA against `git rev-parse HEAD`.
3. **Synchronization:** Executes a `git reset --hard` if a delta is detected.
4. **Hardened Build:** Rebuilds the Docker image with fresh OS patches (`--no-cache`).
5. **Orchestration:** Seamlessly swaps the container bound to `localhost:80`.

## 🚀 Quick Start (IaC Deployment)

Requires Terraform CLI and an authenticated GCP project.

```bash
# 1. Initialize and connect to Remote GCS State
terraform init

# 2. Review the plan
terraform plan

# 3. Provision the entire stack
terraform apply
```

---
*Architected and maintained by [Sreeram K R](https://sreeramkr.com).*
 finished architecting my Zero-Trust GitOps environment on GCP via Terraform. Live case study here: sreeramkr.com
