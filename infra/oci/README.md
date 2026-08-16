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
- cloud-init: installs `cloudflared`, decodes the tunnel token into
  `/etc/cloudflared/<id>.json`, writes ingress config (`ssh.sreeramkr.com → ssh://localhost:22`, catch-all 404), installs the systemd service

## One-time setup (Console)

1. **Upgrade to PAYG** — `Billing → Upgrade` (needed for reliable A1 capacity; Always Free resources stay free).
2. **API key** — `Profile → API keys → Add`; upload the public key, copy:
   - **tenancy OCID** → secret `OCI_TENANCY_OCID`
   - **user OCID** → secret `OCI_USER_OCID`
   - **fingerprint** → secret `OCI_FINGERPRINT`
   - **private key PEM contents** → secret `OCI_API_KEY`
3. **SSH keypair** for the VM (`ssh-keygen -t ed25519 -f ~/.ssh/portfolio`):
   - public key → **variable** `OCI_SSH_PUBLIC_KEY`
   - keep the private key locally (used by `scripts/oci-ssh.sh`)
4. **tfstate bucket name** → **variable** `OCI_TFSTATE_BUCKET` (e.g. `portfolio-tfstate`; bucket is auto-created by the workflow).
5. Confirm the existing **`CLOUDFLARE_TUNNEL_TOKEN`** secret's tunnel still exists:
   `Cloudflare dashboard → Zero Trust → Networks → Tunnels` — note its name.
6. **Tunnel endpoint** — on that tunnel: `Public Hostname → Add`:
   `ssh.sreeramkr.com`, service **SSH**, URL `localhost:22` (creates the DNS CNAME).
7. *(Recommended)* **Zero Trust Access app**: `Access → Applications → Add self-hosted`, domain `ssh.sreeramkr.com`, policy = Allow your email. Without this the hostname is public (key auth still required).

## Deploy

Push to `main` (paths `infra/oci/**`) or run **Actions → OCI Provision → Run workflow**.

> Note: because `hermes-setup.yml` watches `infra/**`, the first push also fires
> the GCP "Hermes Setup" workflow once. It is a harmless no-op apply on the GCP
> infra (untouched); ignore it. (Trigger narrowing is deliberately deferred.)

## SSH (no open ports)

```bash
./scripts/oci-ssh.sh --key ~/.ssh/portfolio
# SSH_KEY=~/.ssh/portfolio ./scripts/oci-ssh.sh
```

First run opens a browser for Cloudflare Access login. Under the hood:
`ssh -o ProxyCommand="cloudflared access ssh --hostname %h" ubuntu@ssh.sreeramkr.com`

Manual equivalent if no Access app:
```bash
ssh -i ~/.ssh/portfolio ubuntu@ssh.sreeramkr.com
```

## Destroy

```bash
# run from a machine with OCI creds, or via workflow (add a destroy input later)
cd infra/oci && terraform destroy
```
