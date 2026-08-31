# Sreeram K R — Portfolio

A live, zero-ingress cloud infrastructure case study: a static portfolio site served from Cloudflare
Pages, with the freed-up free-tier compute re-purposed into a hardened self-hosted password vault.
Everything runs at **$0/month**, with no public ports.

## Quick links

- **Live site**: https://sreeramkr.com
- **The full story** (every phase, with architecture diagrams): https://sreeramkr.com/archive
- **Resume (HTML)**: https://sreeramkr.com/resume.html
- **Resume (PDF)**: https://sreeramkr.com/resume.pdf

## What this repo is

A case study in zero-ingress infrastructure on free-tier cloud. It started as a plain static site on a
VM and evolved through six phases — from a pull-based GitOps loop, to a serverless rebuild, back to a
zero-public-ports Docker Compose host behind a Cloudflare Tunnel, to the edge, and on to re-purposing the
compute into an AI host and a self-hosted password vault.

**The single source of truth for the story is the site's [`/archive`](https://sreeramkr.com/archive).**
Each phase there has its own architecture diagram plus the *why* and *how* behind it, all grounded in the
commit history in this repository.

## Repository layout

```
site/                 Static site (Cloudflare Pages) — index.html, archive.html, resume.html, assets/
infra/                Terraform for GCP (main.tf) + Oracle (oci/) + Vaultwarden compose + backup.sh
scripts/              render-pdf.sh (ATS-safe resume PDF), check-jsonld.mjs, hermes-install.sh
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
