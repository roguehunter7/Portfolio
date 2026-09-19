# Sreeram K R — Portfolio

A live cloud infrastructure case study with no open ports: a static portfolio site on Cloudflare Pages,
plus free-tier compute re-purposed into an Oracle box running Hermes under systemd (SSH and the web
dashboard loopback-bound behind Cloudflare Access) and a self-hosted password vault. Everything runs at
**$0/month**, with no open ports.

## Quick links

- **Live site**: https://sreeramkr.com
- **The full story** (every phase, with architecture diagrams): https://sreeramkr.com/archive
- **Resume (HTML)**: https://sreeramkr.com/resume.html
- **Resume (PDF)**: https://sreeramkr.com/resume.pdf

## What this repo is

A case study in free-tier cloud infrastructure with no open ports. It started as a plain static site on a
VM and evolved through seven phases — from a pull-based GitOps loop, to a serverless rebuild, back to a
Docker Compose host with no open ports behind a Cloudflare Tunnel, to the edge, and on to re-purposing the
compute into an AI host and a self-hosted password vault.

The Oracle A1.Flex box is the workhorse with no open ports, running Ubuntu 24.04: Hermes installed
natively under systemd as the only workload, with the web dashboard (`hermes.sreeramkr.com`) and admin
SSH (`ssh.sreeramkr.com`) carried over the Cloudflare Tunnel and gated by Access. State is snapshotted
to a private OCI Object Storage bucket every six hours, and a rebuild restores it automatically.

**The single source of truth for the story is the site's [`/archive`](https://sreeramkr.com/archive).**
Each phase there has its own architecture diagram plus the *why* and *how* behind it, all grounded in the
commit history in this repository.

## Repository layout

```
site/                 Static site (Cloudflare Pages) — index.html, archive.html, resume.html, assets/
infra/                Terraform for GCP (main.tf) + Oracle (oci/) + Vaultwarden compose + backup.sh/restore.sh
infra/hermes/         Hermes Agent model config (every call runs DeepSeek v4-flash)
infra/oci/            Ubuntu 24.04 Hermes host — Terraform, cloud-init, runbook
scripts/              provision.sh (first boot), maintenance.sh (monthly),
                      hermes-backup.sh / hermes-restore.sh (OCI snapshots),
                      check-cloud-init.py (CI guard), render-pdf.sh
tools/                og-source.html — source for the 1200x630 social card (not deployed)
resume.json           Master resume data (machine-readable, long-form)
.github/workflows/    Deploy (Pages), OCI Provision, Vaultwarden Setup (all manual dispatch)
```

## Deploying

The site is static and deployed to Cloudflare Pages:

```bash
bash scripts/render-pdf.sh site/resume.html site/resume.pdf   # render the ATS-safe PDF
npx wrangler pages deploy site --project-name=portfolio
```

## License

MIT.
