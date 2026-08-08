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

## 📁 Repository Layout

```
site/index.html, site/404.html    Static portfolio site (mermaid via pinned CDN + SRI)
site/resume.html + site/fonts/     Resume source of truth — self-contained HTML+CSS (Source Sans Pro woff2)
resume.json                       Master resume data — machine-readable, long-form (future LLM-tailoring source)
scripts/render-pdf.sh              site/resume.html → site/resume.pdf via headless Chrome + ATS assertions
archive/                           Docker-era files (Dockerfile, compose, deploy.sh, default.conf) — historical
infra/main.tf, infra/variables.tf  Terraform: zero-trust VPC, IAP-only SSH, e2-micro VM = Hermes agent host
.github/workflows/deploy.yml       CI/CD: render resume → Cloudflare Pages deploy
.github/workflows/hermes-setup.yml Manual: provision VM + install Hermes (destroy/rebuild inputs)
scripts/hermes-install.sh          Hermes install + Gemini/Telegram gateway config (run on VM via IAP)
site/resume.pdf                    Generated artifact (gitignored, produced by CI)
```

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

## 🏁 Phase 5: Zero-Ingress VM (Historical — now the Hermes host)

The `e2-micro` VM (GCP Always Free Tier, $0/month) evolved: it served the site through the tunnel (Docker/nginx, 2025–2026), the site moved to Cloudflare Pages (Phase 6, 2026-08), and the VM was **rebuilt as the Hermes agent host** — minimal Debian 13, 25 GB disk, no Docker, no tunnel. Design:

1. **IAP-only SSH** — the only ingress path is GCP Identity-Aware Proxy over port 22 (`35.235.240.0/20`).
2. **No public exposure** — deny-all-ingress firewall; the VM stays invisible to internet scanners.
3. **Hermes (Telegram bot)** — gateway connects *outbound* (Telegram polling + Gemini API); no inbound ports, no tunnel needed.

### 🤖 Hermes Agent (Phase 7)

Hermes (Nous Research) runs on the VM as an unprivileged `hermes` user, answering on Telegram with a DeepSeek backend:

- **Models**: main + all sub-agents/auxiliary `deepseek-v4-flash` (DeepSeek's budget tier; paid API, no free tier — ~10× cheaper than Gemini paid, which requires a ₹1000 minimum top-up)
- **Memory**: 1 GB RAM + 2 GB zram + 6 GB swapfile (`vm.swappiness=180`, `vm.page-cluster=0`)
- **Service**: user systemd unit `hermes-gateway` (official `hermes gateway install`) + `loginctl enable-linger` for boot start
- **Security**: agent runs unprivileged (remote code-execution engine = contained to its home); DM pairing or `TELEGRAM_ALLOWED_USERS` allowlist gates access

Re-provision (Actions → **Hermes Setup**, on `main`):

| `destroy_vm` | `rebuild_vm` | Effect |
|---|---|---|
| ❌ | ❌ | Idempotent apply + install |
| ❌ | ✅ | `-replace` instance → fresh rebuild |
| ✅ | ❌ | `terraform destroy` only |
| ✅ | ✅ | Nuke + rebuild in one run |

**Secrets/vars used**: `DEEPSEEK_API_KEY` (platform.deepseek.com, prepaid top-up) + `TELEGRAM_BOT_TOKEN` (secrets), `TELEGRAM_ALLOWED_USERS` (optional var, Telegram numeric IDs), GCP WIF vars. Nothing is committed or echoed.

---

## ⚡ Phase 6: Cloudflare Pages (Current)

The site is served directly from **Cloudflare Pages** — static assets at the edge, no server. Deployment is fully automated via GitHub Actions:

```
[Developer Push]
       │
       ▼
 1. Cache Check  ──(Hit)──► [Skip HTML Resume Render]
       │
    (Miss)
       │
       ▼
 2. HTML Render  ─────────► [site/resume.html → site/resume.pdf via headless Chrome + ATS assertions]
       │
       ▼
 3. Pages Deploy ─────────► [wrangler pages deploy site → portfolio.pages.dev]
```

### 1. HTML Resume Render

* `site/resume.html` (self-contained HTML+CSS, Source Sans Pro woff2 in `site/fonts/`) is the single source of truth for the resume.
* `scripts/render-pdf.sh` renders it to `site/resume.pdf` using the runner's preinstalled headless Chrome (`--headless=new --print-to-pdf`), then asserts ATS-safety: exactly 1 letter page (`pdfinfo`), key text extractable, and sections in document order (`pdftotext`).
* The workflow checks if `site/resume.html`/`site/fonts/*` changed since the last build; a cache hit skips the ~10s render.

### 2. Cloudflare Pages Deploy & Hardening

* `wrangler pages deploy site/` uploads the static assets (including the rendered `resume.pdf`) to the `portfolio` Pages project — the project is auto-created on first deploy.
* `site/_headers` applies security headers at the edge: hardened CSP (static nonce + pinned mermaid CDN URL only), HSTS, COOP/CORP, Permissions-Policy lockdown, `Cache-Control: no-cache` on `/resume.pdf`, immutable cache on `/fonts/*`.
* `site/.well-known/security.txt` declares the security contact.
* Requires GitHub secrets `CLOUDFLARE_API_TOKEN` (Pages:Edit) and `CLOUDFLARE_ACCOUNT_ID`.

### 3. Hermes — the VM's current job

The Phase 5 `e2-micro` VM no longer serves the site (Pages does). It now runs **Hermes**, a self-hosted AI assistant: Telegram gateway + Gemini API behind the same Cloudflare Tunnel, managed via `scripts/hermes-install.sh` (idempotent) and the manual `hermes-setup` workflow. See Phase 5 below.

### 4. resume.json (master data)

`resume.json` at the repo root holds every fact about the career in long-form (context, why, impact, evidence per achievement). The 1-page `site/resume.html` is a hand-curated projection of it; the planned pipeline is `resume.json + job description → LLM → resume.pdf`. Add raw material freely — it is intentionally not the final resume text.

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

Automating resume PDF builds saves developer overhead, but caching the rendered PDF prevents pipeline bottlenecks, cutting deployment times by **75%** on typical code-only pushes.

### 5. HTML+CSS Resume over LaTeX

The resume is authored once in `resume.html` (self-contained HTML+CSS) and serves both surfaces: the live `/resume.html` page and the `/resume.pdf` download, rendered by headless Chrome in CI. Compared to the former `resume.tex`:

* **ATS-safe by construction** — Chrome writes a real, selectable text layer; CI asserts exactly 1 page (`pdfinfo`) and key-field extraction (`pdftotext`), the same check ATS parsers run.
* **One source, two outputs** — no design drift between the site and the PDF; layout matches the portfolio's typography (Source Sans Pro, `#00529C` accent).
* **No TeX toolchain** — a ~10s render step (and cache) replaces a ~1.5 min LaTeX compilation action.

---

*Architected and maintained by [Sreeram K R](https://sreeramkr.com).*
