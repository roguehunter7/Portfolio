# 🛡️ Serverless Cloud Infrastructure & GitOps Pipeline

![GCP](https://img.shields.io/badge/Google_Cloud-4285F4?style=for-the-badge&logo=google-cloud&logoColor=white)
![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?style=for-the-badge&logo=terraform&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/github%20actions-%232671E5.svg?style=for-the-badge&logo=githubactions&logoColor=white)
![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=for-the-badge&logo=docker&logoColor=white)
![Nginx](https://img.shields.io/badge/nginx-%23009639.svg?style=for-the-badge&logo=nginx&logoColor=white)

## 📌 Overview
This repository contains the **Infrastructure as Code (IaC)** and deployment workflow for a secure, serverless, keyless cloud portfolio site. 

Originally designed as a zero-ingress VM-based setup (using Cloudflare tunnels and custom systemd metrics daemons), the project has evolved into a fully managed, stateless serverless application on **Google Cloud Run**, deployed via **GitHub Actions** using keyless authentication (**Workload Identity Federation**).

---

## 🏗️ Architecture Design

```
  [USER] ─── (HTTPS) ───► [CLOUD RUN INGRESS] ───► [UNPRIVILEGED NGINX CONTAINER]
                                                        (index.html & resume.pdf)
                                                                   ▲
                                                                   │ (Deploy)
[GITHUB ACTIONS] ─── (OIDC/WIF) ───► [GCP ARTIFACT REGISTRY] ──────┘
```

---

## 🧠 Core Engineering Decisions

### 1. Keyless CI/CD with Workload Identity Federation (WIF)
We eliminated all long-lived Google Cloud Service Account JSON keys from GitHub Secrets. The deployment pipeline authenticates securely using short-lived OpenID Connect (OIDC) tokens through GCP Workload Identity Federation, drastically reducing the security risk profile.

### 2. Fully Managed Serverless Hosting
Migrated from a self-managed `e2-micro` VM to **Google Cloud Run**. The application scales down to zero instances when idle, removing host OS maintenance, security patching overhead, and daemon service monitoring.

### 3. State-Locked Declarative IaC
The infrastructure (Cloud Run service and public IAM bindings) is defined declaratively using **Terraform** with state locked in a **GCS Remote Backend**. The pipeline automatically applies modifications on push to the `main` branch.

### 4. LaTeX Resume Automation with Caching
The pipeline compiles `resume.tex` to `resume.pdf` during the workflow run. To optimize deployment speed, `actions/cache` is used to cache `resume.pdf` based on the hash of `resume.tex`.
* **Deployment Optimization:** If `resume.tex` has not changed, the LaTeX setup and compilation step are skipped completely, saving ~1.5 minutes per run.

### 5. Runtime Hardening
The portfolio is served using `nginxinc/nginx-unprivileged:1.27.0-alpine-slim` running on non-root UID 101, safeguarding the environment against container-escape vulnerabilities.

---

## 📂 Repository Structure

* `main.tf` : Terraform configuration for the Cloud Run v2 service and public access bindings (`roles/run.invoker` for `allUsers`).
* `variables.tf` : Declarative input variables for container tags.
* `Dockerfile` : Configured to optionally copy `resume.pdf` using wildcards to protect local/dev builds if the PDF hasn't been compiled locally.
* `index.html` : The main web page detailing the 4-phase architectural evolution.
* `resume.tex` : The LaTeX source file for the professional resume.
* `.github/workflows/deploy.yml` : Secure CI/CD workflow utilizing OIDC auth, LaTeX caching, Docker builds, and Terraform apply.

---

## ⚙️ Automated Deployment Flow

1. **Change Detection & Cache Check:** GitHub Actions checks if `resume.tex` has changed. If unchanged, it restores `resume.pdf` from the cache.
2. **LaTeX Compilation (Conditional):** If the cache is missed, it compiles `resume.tex` into `resume.pdf`.
3. **Hardened Containerization:** The runner builds the unprivileged Nginx image, copying both `index.html` and `resume.pdf` (if present) into the image, and pushes it to GCP Artifact Registry using OIDC authentication.
4. **Declarative Deploy:** Runs `terraform init` and `terraform apply` using the new image tag, deploying the service and ensuring public web ingress access.

---

## 🚀 Quick Start (IaC Deployment)

To configure or modify the infrastructure locally, authenticate with `gcloud` and run:

```bash
# 1. Initialize and connect to Remote GCS State
terraform init -reconfigure

# 2. Review the plan
terraform plan -var="container_image_tag=us-central1-docker.pkg.dev/main-project-402906/portfolio-registry/portfolio-app:latest"

# 3. Provision modifications
terraform apply -var="container_image_tag=us-central1-docker.pkg.dev/main-project-402906/portfolio-registry/portfolio-app:latest"
```

---
*Architected and maintained by [Sreeram K R](https://sreeramkr.com).*
