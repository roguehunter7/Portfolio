# Sreeram K R | Portfolio

A live case study in free-tier cloud infrastructure. A static portfolio on Cloudflare Pages, a Hermes
assistant and a self-hosted password vault on two free-tier boxes, no open ports anywhere, and
**$0/month**.

## Quick links

- Live site: https://sreeramkr.com
- The full story, every phase with architecture diagrams: https://sreeramkr.com/archive
- Resume (HTML): https://sreeramkr.com/resume.html
- Resume (PDF): https://sreeramkr.com/resume.pdf

## What this repo is

The site started on one hand-built VM and moved through eight phases: a GitOps polling loop that redeployed
on every commit, a serverless rebuild that cost more than it was worth, a retreat to a single VM with no open
ports, a move to the edge, and finally two free-tier boxes running an assistant and a vault. The reversals are
part of the story, so they stayed in.

The Oracle box does the work: Ubuntu 24.04, Hermes native under systemd, SSH and dashboard over the
Cloudflare Tunnel behind Access, six-hourly snapshots to OCI Object Storage. Full runbook in
`infra/oci/README.md`.

The single source of truth for the story is the site's [`/archive`](https://sreeramkr.com/archive).
Each phase there has its own architecture diagram plus the *why* and *how* behind it, all grounded in the
commit history in this repository.

## Repository layout

```
site/                 Static site (Cloudflare Pages): index.html, archive.html, resume.html, assets/
infra/                Terraform for GCP (main.tf) + Oracle (oci/) + Vaultwarden compose + backup.sh/restore.sh
infra/hermes/         Hermes Agent model config (every call runs DeepSeek v4-flash)
infra/oci/            Ubuntu 24.04 Hermes host: Terraform, cloud-init, runbook
scripts/              provision.sh (first boot), maintenance.sh (monthly),
                      hermes-backup.sh / hermes-restore.sh (OCI snapshots),
                      check-cloud-init.py (CI guard), render-pdf.sh
tools/                og-source.html (source for the 1200x630 social card) and diagrams/ (Archify
                      specs; only the current phase has one, the rest were generated ad hoc)
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
