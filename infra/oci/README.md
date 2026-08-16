# infra/oci — Oracle Cloud VM (Phase 8)

Zero-ingress Oracle VM provisioned by GitHub Actions + Terraform. SSH reaches it
**only via the existing Cloudflare tunnel** — the VM has **no public ports**.

## Always Free compliance (verified against official docs, 2026-08)

| Component | Config | Always Free limit | Verdict |
|---|---|---|---|
| Compute | `VM.Standard.A1.Flex`, 2 OCPU / 12 GB | 1,500 OCPU-hrs + 9,000 GB-hrs/mo (= 2 OCPU / 12 GB continuous; Oracle halved the old 4/24 in June 2026) | ✅ within |
| Block volume | boot volume 50 GB | 200 GB total (boot + block) | ✅ within |
| Object Storage | tfstate bucket (KB-size) | 20 GB | ✅ within |
| Networking | VCN, IGW, route table, subnet, NSG, 1 ephemeral public IP | all $0; no NAT gateway used (free-tier ambiguity avoided) | ✅ within |
| SSH transport | cloudflared tunnel (outbound) | tunnel itself is free; Cloudflare Zero Trust free plan | ✅ free |
| Image | Canonical Ubuntu 24.04 (ARM64) | Always Free-eligible platform image, no license fee | ✅ within |
| Egress | 10 TB/mo outbound | not approached | ✅ |

**Caveats**
- Oracle may **reclaim idle A1 instances** (CPU/network/mem < 20% for 7 days). Keep the box busy (SSH sessions count).
- The `cloudflare_tunnel_token` is injected via cloud-init and therefore lands in
  the OCI tfstate (private bucket) + instance metadata. Scope of the token: it
  can only run the tunnel — it cannot manage OCI. Acceptable for this project.

## Architecture

```
your laptop ── cloudflared access ssh ──> Cloudflare edge ──> cloudflared (on VM, outbound)
                                                                  └─> ssh://localhost:22 (sshd)
VM: public IP exists but NSG has ZERO ingress rules → nothing reachable from the internet
```

- VCN `10.0.0.0/16`, public subnet `10.0.0.0/24`, IGW + default route
- NSG `instance-nsg`: **no rules** (= deny-all ingress)
- A1.Flex 2 OCPU / 12 GB, Ubuntu 24.04 ARM64, 50 GB boot, ephemeral public IP (egress only)
- cloud-init: installs `cloudflared` and registers the remote-managed tunnel
  via its token (ingress routes live in the Cloudflare dashboard — `ssh.sreeramkr.com
  → ttyd on :7681`); installs Node LTS + Reasonix via nvm, ttyd+tmux browser
  terminal, weekly maintenance (upgrade + reboot, Mon 02:00), and host hardening
  (ufw deny-incoming, sshd off)

## One-time setup (Console)

The CI workflow reads credentials from GitHub **Secrets / Variables** (exact
names are in `.github/workflows/oci-provision.yml`). Configure:

1. **Upgrade to PAYG** — `Billing → Upgrade` (needed for reliable A1 capacity; Always Free resources stay free).
2. **OCI API key** — `Profile → API keys → Add`; upload the public key, then store the tenancy OCID, user OCID, fingerprint, and private key PEM contents as GitHub secrets.
3. **SSH keypair** for the VM (`ssh-keygen -t ed25519 -f ~/.ssh/portfolio`) — public key as a GitHub variable (the private key is only a fallback/console path; the primary admin access is the browser terminal).
4. **tfstate bucket name** as a GitHub variable (e.g. `portfolio-tfstate`; bucket is auto-created by the workflow).
5. Confirm the existing **Cloudflare tunnel token** secret's tunnel still exists:
   `Cloudflare dashboard → Zero Trust → Networks → Tunnels` — note its name.
6. **Browser terminal password** as a GitHub secret (used by the ttyd login).
7. **Tunnel endpoint** — on that tunnel: `Public Hostname → Add`:
   `ssh.sreeramkr.com`, service **HTTP**, URL `localhost:7681` (creates the DNS CNAME).
8. *(Recommended)* **Zero Trust Access app**: `Access → Applications → Add self-hosted`, domain `ssh.sreeramkr.com`, policy = Allow your email.

## Deploy

Run **Actions → OCI Provision → Run workflow** (manual `workflow_dispatch` only).

> Note: because `hermes-setup.yml` watches `infra/**`, the first push also fires
> the GCP "Hermes Setup" workflow once. It is a harmless no-op apply on the GCP
> infra (untouched); ignore it. (Trigger narrowing is deliberately deferred.)

## Access (browser terminal — zero open ports)

Open **https://ssh.sreeramkr.com** → log in with your configured ttyd credentials
(user `sreeram` + the password you set as a GitHub secret) → lands in a tmux
session (`main`) on the VM.

- Multiple terminals: `Ctrl-b c` (new tmux window), `Ctrl-b %` / `Ctrl-b "` (split panes)
- Detach/reattach: close the tab, reopen — tmux keeps your session (Reasonix keeps running)
- Node/reasonix are installed via nvm for the `ubuntu` user (no sudo needed)

Emergency backdoor (if the tunnel is down): OCI serial console
(`Compute → instance → Resources → Console connection`).

## Destroy

```bash
# run from a machine with OCI creds, or via workflow (add a destroy input later)
cd infra/oci && terraform destroy
```
