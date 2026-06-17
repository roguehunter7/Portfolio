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

    [USER] --- (HTTPS) --- [CLOUDFLARE EDGE]
                                 │
    [ACTIONS] --- (IAP) --- [GCP FIREWALL] (DENY ALL PUBLIC)
                                 │
                                 ▼
                    [GCP DEBIAN COMPUTE NODE]
                                 │
                    ├─ [cloudflared] (Tunnel to Edge)
                    └─ [Docker] (nginx-unprivileged:alpine-slim)

## 🧠 Core Engineering Decisions

### 1. Push-Based CI/CD with IAP Tunneling
To maintain a 100% closed-port security posture, I utilized **GCP Identity-Aware Proxy (IAP)**. GitHub Actions authenticates via a service account and establishes a temporary SSH tunnel through IAP's internal IP range (`35.235.240.0/20`). This allows for secure, automated deployments without ever opening Port 22 to the public internet.

### 2. Runtime Hardening (Non-Root)
The application is deployed using the `nginx-unprivileged:alpine-slim` base image. The process runs as UID 101, preventing potential "Container Breakout" exploits from gaining root access to the host OS.

### 3. State-Locked IaC
Infrastructure is managed via **Terraform** using a **GCS Remote Backend**. This ensures state consistency across different development environments and provides an audit trail of all infrastructure changes.

### 4. DevSecOps Image Hardening
To remediate upstream vulnerabilities in the `nginx:alpine` base image, the build process injects an automated OS-level package patch (`apk upgrade`) during the containerization phase.

### 5. Native Live Server Telemetry
Configured Nginx's native `stub_status` module to securely expose real-time metrics (`/status`) over the Cloudflare tunnel. The frontend page performs periodic client-side polling to dynamically display active connection counts and total processed requests in the footer without requiring heavy third-party tracking or monitoring agents.

## 📂 Repository Structure

* `main.tf` : Terraform configuration for VPC, Firewalls, and Compute.
* `main.html` : The frontend portfolio case study.
* `Dockerfile` : Nginx-Alpine configuration with integrated security patching.
* `deploy.sh` : The core CD logic. Uses native Git to poll SHAs and manage Docker lifecycles.

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
