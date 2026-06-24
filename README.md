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

---

## 🧠 Core Engineering Decisions

### 1. Keyless CI/CD with Workload Identity Federation (WIF)

We eliminated all long-lived Google Cloud Service Account JSON keys from GitHub Secrets. The deployment pipeline authenticates securely using short-lived OpenID Connect (OIDC) tokens through GCP Workload Identity Federation, drastically reducing the security risk profile.

### 2. Fully Managed Serverless Hosting

Migrated from a self-managed `e2-micro` VM to **Google Cloud Run**. Both the static web app and the visitor tracker microservice are hosted on Cloud Run. The services scale down to zero instances when idle, removing host OS maintenance and daemon service monitoring.

### 3. Serverless Go & Firestore Visitor Analytics

Implemented a custom visitor and active session tracker API in **Go (Golang)**. It connects to **Google Cloud Firestore (Native Mode)** to record live session metadata and atomically increment unique site views.
- **Resource Footprint Optimization:** The Go microservice runs within a resource-restricted container limited to `128Mi` memory, utilizing `cpu_idle = true` to throttle CPU during inactivity, reducing idle container costs to zero.
- **Session Lifecycle & Bloat Prevention:** The API writes ephemeral active session documents and executes auto-eviction queries to delete sessions older than 5 minutes, preventing Firestore database bloat.
- **Cache Control & CORS:** Sends strict no-cache headers to ensure metrics remain fresh, and includes proper CORS configuration for seamless client integration.

### 4. State-Locked Declarative IaC

The infrastructure (Cloud Run services and public IAM invoker bindings) is defined declaratively using **Terraform** with state locked in a **GCS Remote Backend**. The pipeline automatically applies modifications on push to the `main` branch.

### 5. LaTeX Resume Automation with Caching

The pipeline compiles `resume.tex` to `resume.pdf` during the workflow run. To optimize deployment speed, `actions/cache` is used to cache `resume.pdf` based on the hash of `resume.tex`.
- **Deployment Optimization:** If `resume.tex` has not changed, the LaTeX setup and compilation step are skipped completely, saving ~1.5 minutes per run.

### 6. Runtime Hardening

The portfolio frontend is served using `nginxinc/nginx-unprivileged:1.27.0-alpine-slim` running on non-root UID 101, safeguarding the environment against container-escape vulnerabilities.

---

## 📂 Repository Structure

* `main.tf` : Terraform configuration for both the frontend and tracker API Cloud Run services, including public access bindings (`roles/run.invoker` for `allUsers`).
* `variables.tf` : Declarative input variables for container tags.
* `Dockerfile` : Configured to optionally copy `resume.pdf` using wildcards to protect local/dev builds if the PDF hasn't been compiled locally.
* `index.html` : The main web page detailing the 4-phase architectural evolution and displaying live session stats in the footer.
* `resume.tex` : The LaTeX source file for the professional resume.
* `tracker-api/` : Go API microservice codebase.
  - `main.go` : The Go listener with Firestore SDK integrations, CORS, and cleanup routines.
  - `Dockerfile` : Multi-stage build (`golang:alpine` to `alpine:latest`) to produce a highly-minimized execution image.
* `.github/workflows/deploy.yml` : Secure CI/CD workflow utilizing OIDC auth, LaTeX caching, Docker builds for both containers, and Terraform apply.

---

## ⚙️ Automated Deployment Flow

1. **Change Detection & Cache Check:** GitHub Actions checks if `resume.tex` has changed. If unchanged, it restores `resume.pdf` from the cache.
2. **LaTeX Compilation (Conditional):** If the cache is missed, it compiles `resume.tex` into `resume.pdf`.
3. **Hardened Containerization:** The runner builds the unprivileged Nginx frontend image and the compiled Go tracker API image, pushing both to GCP Artifact Registry using OIDC authentication.
4. **Declarative Deploy:** Runs `terraform init` and `terraform apply` using the new image tags, deploying/updating both Cloud Run services and ensuring public web ingress access.

---

*Architected and maintained by [Sreeram K R](https://sreeramkr.com).*
