# MASTER AGENT DIRECTIVES 
## 1. Minimal Code Decision Ladder (Ponytail Mode)
Before writing code, walk this ladder and stop at the first rung:
1. YAGNI: Does this code need to exist? If no -> skip.
2. Stdlib: Does standard library do it? -> use stdlib.
3. Native Platform: Does HTML5/OS/browser do it natively? -> use native.
4. Installed Deps: Does an existing project package do it? -> use package.
5. Minimum Block: Write only the absolute minimum required code.

## 2. Terse Prose Output (Caveman Mode)
- Cut all greetings, pleasantries, wind-up, and commentary ("Sure, I can help...", "I will now edit...").
- Output direct, high-density fragments.
- Mandated response format:
  * **[Analysis]** -> 1-sentence root cause.
  * **[Action]** -> Applied tool command / file edit.
  * **[Verification]** -> Terminal test or linter output confirming fix.

## 3. Strict Anti-Hallucination & Fact-Checking
- IF YOU DO NOT HAVE 100% CONFIDENCE IN AN API METHOD, PACKAGE SIGNATURE, OR CLI FLAG, EXECUTE A SEARCH TOOL OR SAY "I DON'T KNOW". NEVER GUESS OR INVENT SYNTAX.
- **Read-Before-Write:** Always read/grep existing source files before writing imports or function calls.

## 4. Code Quality & Non-Truncation Rules
- **NO PLACEHOLDERS:** NEVER output `// ... rest of file unchanged`. Write complete, valid code blocks.
- **ISOLATED SCOPE:** Do NOT reformat or touch unrelated code/comments.
- **SAFETY CARVE-OUT (NON-NEGOTIABLE):** NEVER compress or omit input validation, authentication, security checks, error handling, or database migrations.

## 5. Self-Correction Loop
- Always execute type-checkers (`tsc --noEmit`), linters (`eslint`, `ruff`), or test runners (`pytest`, `npm test`) using terminal tools to verify changes before returning control to the user.

---

# Portfolio — Project Facts

## Project
Zero-ingress portfolio (sreeramkr.com) + infrastructure case study. Stack: vanilla HTML/CSS/JS static site on **Cloudflare Pages** (direct upload via wrangler), resume rendered to PDF in CI via headless Chrome; **e2-micro VM (infra/) = Hermes agent host** (minimal Debian 13, 25 GB, zram+swap, no Docker, no tunnel — IAP-only SSH). No framework, no build step, no test suite.

## Master Plan — End Goal (north star, agreed 2026-08; implement incrementally)
Single repo `roguehunter7/Portfolio`, all services zero-ingress, secrets only in GitHub Secrets (never committed), staying inside Oracle Always Free limits:

1. **Cloudflare Pages (edge, VM-independent):** `sreeramkr.com` = centerpoint (current state + services hub + resume); `archive.sreeramkr.com` = full case-study history page; Ghost blog lives on the VM, not Pages (dynamic).
2. **Oracle Cloud Always Free** (PAYG, never exceeding free limits), one `VM.Standard.A1.Flex` (4 OCPU/24 GB): **Vaultwarden** (`vault.sreeramkr.com`, Docker Compose + cloudflared); **Ghost** (`blog.sreeramkr.com` = **job-application showcase**: bare-metal `ghost-cli` + systemd + host Nginx + MySQL 8 + cloudflared — deliberately NOT the Ghost 6.0 docker-compose default [ghost+caddy+mysql]; real content; recorded as a Loom demo, hybrid intro if the brief asks for a self-intro); **Hermes** (external project, outbound-only, DeepSeek backend); **Reasonix dev box**.
3. **Zero-ingress posture:** deny-all ingress, admin only via OCI Bastion (IAP analog), all public ingress through Cloudflare Tunnel.
4. **Provisioning:** GitHub Actions (OIDC → OCI session token, keyless) + Terraform + idempotent bash scripts.
5. **Backups:** nightly SQLite dump (Vaultwarden) + Ghost DB dump → OCI Object Storage with retention; restore documented.
6. **GCP decommission:** e2-micro `terraform destroy`, GCP WIF vars/secrets removed.

**Why:** Ghost deployment on a non-default stack is the differentiator for a job application at the Ghost company (beats a self-introduction video); the rest is a free-tier zero-ingress infrastructure case study.

**How to apply:** Plan incremental phases against this north star (site/archive first, then Oracle VM, then services). Keep: single repo, zero-ingress, Oracle Always Free limits, secrets only in GitHub Secrets.

## Commands
```bash
# CI-only deploy path (push to main triggers .github/workflows/deploy.yml)
# render resume + wrangler pages deploy (needs CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID secrets)
npx --yes wrangler@4 pages deploy site --project-name=portfolio
# Local resume render + ATS checks (1 page, text, section order)
bash scripts/render-pdf.sh site/resume.html site/resume.pdf
# Legacy VM terraform (infra/): terraform apply -auto-approve (no vars; cloudflared/tunnel removed 2026-08)
# Health
curl -sSf https://sreeramkr.com
```
No linter/test runner configured. resume.pdf is rendered from site/resume.html via scripts/render-pdf.sh (headless Chrome --print-to-pdf, cache keyed on hashFiles('site/resume.html','site/fonts/*')) with pdfinfo/pdftotext ATS assertions (1 page, key text, section order) inside the script.

## Architecture
1. **Site** — `site/index.html` + `site/404.html` + `site/resume.pdf` (rendered from `site/resume.html` by CI) + `site/resume.html` (live); mermaid via pinned jsdelivr CDN URL + SRI; static CSP nonce `p0rtfolio-s1te`; security headers in `site/_headers` (Pages edge).
2. **Pages** — Cloudflare Pages project `portfolio`, direct upload of `site/` via `wrangler pages deploy`; project auto-created on first deploy; custom domain sreeramkr.com; `X-Robots-Tag: noindex` on *.pages.dev.
3. **Archive (legacy, on hold)** — `archive/` (Dockerfile, default.conf, docker-compose.yml, deploy.sh) + `infra/` (main.tf/variables.tf: zero-trust VPC, deny-all-ingress, IAP-only SSH, e2-micro debian-13). No longer executed by CI.
4. **CI** — `.github/workflows/deploy.yml`: cache resume.pdf → render-pdf.sh → wrangler pages deploy; secrets CLOUDFLARE_API_TOKEN + CLOUDFLARE_ACCOUNT_ID; contents: read only.
5. **Hermes** — `.github/workflows/hermes-setup.yml` (manual, inputs destroy_vm/rebuild_vm): WIF → terraform (infra/) → IAP SSH → scripts/hermes-install.sh; user service hermes-gateway via official `hermes gateway install` + linger; secrets GEMINI_API_KEY + TELEGRAM_BOT_TOKEN (passed as SSH env, never echoed), var TELEGRAM_ALLOWED_USERS; models gemini-flash-latest / delegation gemini-flash-lite-latest.
6. **History** — former PROJECT.md (Cloudflare Pages, Vaultwarden, Hermes agent) deleted 2026-08; resume pipeline HTML→PDF via headless Chrome (no LaTeX); site migrated to Pages 2026-08 (Phase 6); VM rebuilt as Hermes host (Phase 7, cloudflared removed).

## Conventions
- Site deploys to Cloudflare Pages via wrangler direct upload; custom domain sreeramkr.com is canonical (pages.dev is noindexed).
- Legacy zero-ingress rules (never map host ports; all inbound via Cloudflare tunnel; SSH only through IAP) apply to the historical `infra/` VM; the Hermes host uses IAP-only SSH and outbound-only traffic (no tunnel).
- Secrets (`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, legacy `CLOUDFLARE_TUNNEL_TOKEN`) live only in GitHub Secrets; passed via env, never committed.
- Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`).
- `REASONIX.md`, `reasonix.toml` are local agent tooling (untracked) — not deployed.

## Notes
(quick additions live here)
