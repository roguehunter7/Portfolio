# Sreeram K R — Portfolio

A live cloud infrastructure case study with no open ports: a static portfolio site served from Cloudflare
Pages, with the freed-up free-tier compute re-purposed into a hardened self-hosted password vault.
Everything runs at **$0/month**, with no open ports.

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

The Oracle A1.Flex dev box is the workhorse with no open ports, running Ubuntu 24.04:
a browser terminal over the Cloudflare Tunnel, the DeepSeek Harness web UI
for on-demand use (`dsh.sreeramkr.com`), and the Hermes AI assistant in the official
Docker container. No open ports.

**The single source of truth for the story is the site's [`/archive`](https://sreeramkr.com/archive).**
Each phase there has its own architecture diagram plus the *why* and *how* behind it, all grounded in the
commit history in this repository.

## Repository layout

```
site/                 Static site (Cloudflare Pages) — index.html, archive.html, resume.html, assets/
infra/                Terraform for GCP (main.tf) + Oracle (oci/) + Vaultwarden compose + backup.sh
infra/hermes/         Hermes Agent config + Docker Compose (all calls DeepSeek v4-flash)
infra/oci/            Ubuntu 24.04 dev box — Terraform, cloud-init, runbook
scripts/              provision.sh (first boot), maintenance.sh (monthly),
                      check-cloud-init.py (CI guard), render-pdf.sh
tools/                og-source.html — source for the 1200x630 social card (not deployed)
resume.json           Master resume data (machine-readable, long-form)
.github/workflows/    Deploy (Pages), OCI Provision, Vaultwarden Setup (all manual dispatch)
```

## Deploying

The site is static and deployed to Cloudflare Pages:

```bash
bash scripts/render-pdf.sh site/resume.html site/resume.pdf   # render + ATS-assert the PDF
npx wrangler pages deploy site --project-name=portfolio
```

The resume PDF pipeline and the infrastructure code (`infra/`, workflows) are unchanged by the site
rebuild.

## License

MIT.
