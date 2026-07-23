# 🛡️ Zero-Ingress Cloud Infrastructure & GitOps Pipeline

[![Live Site](https://img.shields.io/badge/Live-sreeramkr.com-60a5fa?style=for-the-badge&logo=google-chrome&logoColor=white)](https://sreeramkr.com)
![GCP](https://img.shields.io/badge/Google_Cloud-4285F4?style=for-the-badge&logo=google-cloud&logoColor=white)
![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/github%20actions-%232671E5.svg?style=for-the-badge&logo=githubactions&logoColor=white)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)
![Nginx](https://img.shields.io/badge/nginx-%23009639.svg?style=for-the-badge&logo=nginx&logoColor=white)
![Cloudflare](https://img.shields.io/badge/Cloudflare-F38020?style=for-the-badge&logo=cloudflare&logoColor=white)

## 📌 Professional Overview

This repository serves as a live, evolving systems engineering case study. It showcases the design, implementation, and deployment of a secure, production-grade personal portfolio website.

Designed with a **Zero-Ingress / Zero-Trust posture**, the architecture exposes no public ports to the internet and has evolved through multiple phases to achieve maximum availability, high security, and strict **cost optimization** ($0/month) within the GCP Always Free Tier.

---

## 🏗️ Architectural Evolution

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 1: Bash GitOps Polling (Host VM, e2-micro, Pull-based)              │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 2: Push-based IAP Tunneling (GitHub Actions, SSH Tunneling via IAP)  │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 3: Telemetry & GHCR (Unprivileged Nginx in Docker, Host systemd)     │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 4: Serverless Migration (Cloud Run, Go API Tracker, Firestore DB)    │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  Phase 5: Cost-Optimized Zero-Ingress VM (Docker Compose, Cloudflare Tunnel)│
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 🏁 Phase 5: Current Production Architecture (Cost Optimization)

To bring monthly operating costs strictly down to **$0**, the infrastructure was migrated from Google Cloud Run back to an `e2-micro` Virtual Machine (fully covered under Google's Always Free Tier). The tracker API and its Firestore database dependencies were retired to avoid storage and API request charges.

### Zero-Ingress Docker Compose Setup

The host VM does not map Nginx's ports (`80` or `8080`) to the host interface, nor are there any open inbound firewall rules from the public internet. Instead:

1. **Cloudflared Container**: Connects outwards to Cloudflare Zero Trust via a secure outbound tunnel.
2. **Private Docker Network**: The `cloudflared` container proxies incoming traffic directly to the `web` container over an isolated, internal Docker bridge network.
3. **No Ingress Ports**: The VM remains a closed box to all incoming traffic except secure SSH management proxied via Identity-Aware Proxy.

---

## ⚙️ Step-by-Step Build & Deployment Pipeline (CI/CD)

The push-based deployment is fully automated using GitHub Actions. Below is a detailed, step-by-step explanation of the execution flow:

```
[Developer Push] 
       │
       ▼
 1. Cache Check  ──(Hit)──► [Skip LaTeX Build]
       │
    (Miss)
       ▼
 2. LaTeX Build  ─────────► [Generate resume.pdf]
       │
       ▼
 3. Docker Build ─────────► [Push to GHCR (Public Package)]
       │
       ▼
 4. OIDC Auth    ─────────► [Authenticate via WIF to GCP]
       │
       ▼
 5. IaC Check    ─────────► [Terraform Apply (VPC, Firewall, VM)]
       │
       ▼
 6. IAP SSH Push ─────────► [gcloud compute ssh via Port 22 Tunnel]
       │
       ▼
 7. VM Deploy    ─────────► [deploy.sh runs Docker Compose up]
```

### 1. LaTeX Resume Cache & Compilation

* The workflow checks if `resume.tex` has been updated since the last build.
* If a cache hit occurs, it retrieves the compiled `resume.pdf` from the GitHub Actions Cache, saving about 1.5 minutes of runner run time.
* If it is a cache miss, it spins up a LaTeX compilation action (`xu-cheng/latex-action`) to compile `resume.tex` into a fresh PDF.

### 2. Hardened Container Build & Push

* The runner builds a Docker image based on `nginxinc/nginx-unprivileged:1.27.0-alpine-slim`.
* This image packages `index.html`, the custom `default.conf` (which exposes the Nginx `/status` endpoint), and the newly compiled `resume.pdf`.
* The container runs under non-root user `nginx` (UID 101) to mitigate container-escape risks.
* The image is tagged with the unique Git commit SHA (`github.sha`) and pushed to **GitHub Container Registry (GHCR)**.

### 3. Federated Authentication via OIDC/WIF

* Rather than storing long-lived GCP service account keys in GitHub Secrets, the runner authenticates using **Workload Identity Federation (WIF)**.
* The workflow exchanges a short-lived GitHub OIDC token for a federated GCP credential.

### 4. Declarative Infrastructure Provisioning (Terraform)

* The runner initializes and applies the Terraform configuration (`main.tf`).
* The state is stored and locked in a Google Cloud Storage (GCS) bucket.
* Terraform provisions/updates the **Zero-Trust VPC**, the **IAP SSH firewall rule**, and the **e2-micro VM instance**.

### 5. Secure Push-Based VM Deployment (IAP Tunneling)

* Once the infrastructure is ready, the runner executes a secure `gcloud compute ssh` command to connect to the GCE VM.
* Because all ingress ports are blocked, the runner tunnels through GCP **Identity-Aware Proxy (IAP)**, which acts as a secure bastion. IAP traffic is restricted to Google's specific range (`35.235.240.0/20`).
* The runner passes the new `IMAGE_TAG` and the `CLOUDFLARE_TUNNEL_TOKEN` repository secret as environment variables across the SSH tunnel.

### 6. Orchestration on the Host VM

* The command executes `/opt/portfolio/deploy.sh` on the VM.
* The script writes the new container tag and tunnel token to a local `.env` file.
* It pulls the new public image from GHCR.
* It launches the Docker Compose services:

  ```bash
  docker-compose up -d --remove-orphans
  ```

* The Nginx server starts up, and the Cloudflare tunnel establishes an outbound connection, bringing the website update live.

---

## 🏛️ Historical Case Study: Phase 4 (Serverless Architecture)

Before the cost-saving migration in Phase 5, the website was architected as a fully managed serverless application.

### Phase 4 Architecture Diagram

```
  [USER] ─── (HTTPS) ───► [PORTFOLIO FRONTEND] ───► [UNPRIVILEGED NGINX]
                                                        (index.html & resume.pdf)
                                                                    │
                                                             (Fetch API / CORS)
                                                                    ▼
  [FIRESTORE DB] ◄─── (atomic sdk) ───► [PORTFOLIO TRACKER API (Go)]
                                           (us-central1, 128Mi, CPU Idle)
                                                                    ▲
                                                                    │ (Deploy)
 [GITHUB ACTIONS] ─── (OIDC/WIF) ───► [GCP ARTIFACT REGISTRY] ──────┘
```

### Serverless Go & Firestore Visitor Analytics

To track visitor analytics serverlessly, we engineered a custom visitor and active session tracker microservice:

* **Go Microservice**: Written in Go using the official Firestore SDK. It listened for HTTP requests, verified CORS, and incremented global view counters.
* **Firestore Native Integration**: Used Firestore to atomically increment the total view count. To track live users, it wrote short-lived session documents.
* **Auto-Eviction & Memory Management**: To keep Firestore database storage minimal, the API executed background query routines to delete session documents older than 5 minutes.
* **Cloud Run Resource Limits**: The Go container was locked to `128Mi` memory limits with `cpu_idle = true` enabled, ensuring that when the API scaled down or sat idle, Google charged $0 for runtime execution.
* **Artifact Registry Fee Pivot**: Despite the Go service itself being free, maintaining container images in GCP Artifact Registry and Firestore data reads/writes incurred small monthly fees. This led to the cost-driven pivot of Phase 5.

---

## 📂 Core Engineering Decisions & Takeaways

### 1. Keyless Auth (WIF) over Service Account Keys

Using OIDC authentication removes the risk of compromised secrets. There are no static JSON credentials that can leak.

### 2. Zero-Ingress Network Security

By utilizing Cloudflare Zero Trust Tunnels and Google IAP, the VM is entirely isolated from internet scanners. There is no public-facing port `22` or `80` to probe.

### 3. Container Isolation vs. Host systemd

Migrating from native host-level daemons (Phase 3) to Docker Compose (Phase 5) isolates the Nginx runtime and the tunneling client. The host OS remains pristine, easy to patch, and free from custom system configuration drift.

### 4. Caching at the Pipeline Level

Automating LaTeX document builds saves developer overhead, but caching the compiled PDFs prevents pipeline bottlenecks, cutting deployment times by **75%** on typical code-only pushes.

---

*Architected and maintained by [Sreeram K R](https://sreeramkr.com).*
