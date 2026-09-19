# infra/oci — Ubuntu 24.04 Hermes host

No-open-ports Oracle A1.Flex provisioned by GitHub Actions + Terraform. The box
runs **Hermes natively** as its own user, and is administered over **SSH carried
by the Cloudflare Tunnel**: `ssh.sreeramkr.com` → `ssh://localhost:22`, and the
Hermes dashboard on `hermes.sreeramkr.com` → `http://localhost:9119`. Cloudflare
Access gates both routes, sshd and the dashboard bind loopback, and `ufw` denies
inbound — so nothing is ever publicly reachable.

## Why Ubuntu 24.04

* It is a first-class OCI platform image for Arm (`Canonical Ubuntu 24.04`), with the
  default `ubuntu` user and native `apt`/`ufw` tooling the provisioning scripts
  are written against.
* Hermes is **not** a distro package. Its installer brings uv-managed Python,
  Node and ripgrep into `/home/hermes`, so a monthly `apt upgrade` cannot break
  the agent and there is no distro Python/Node version to track. The only OS
  packages the installer needs are `git`, `curl` and `xz-utils`.

## Workloads

| Workload | How it runs | Reachable at |
|---|---|---|
| Cloudflare Tunnel | `cloudflared.service`, outbound | the only ingress path |
| SSH (admin + CI) | `sshd`, loopback `:22`, user `ubuntu` | `ssh.sreeramkr.com` (Access) |
| Hermes gateway | `hermes-gateway.service`, user `hermes` | Telegram (long poll, outbound) |
| Hermes dashboard | `hermes-dashboard.service`, loopback `:9119` | `hermes.sreeramkr.com` (Access) |

Nothing else runs on the host. There is no Docker, no multiplexer and no browser
terminal: SSH is the admin path and Hermes is the workload.

## Blast radius — read this before changing anything

The `hermes` user has **full sudo by design** (`/etc/sudoers.d/hermes`). Hermes is
the control surface on this box, so the agent is root-equivalent on purpose. The
consequences, stated plainly:

* The box holds the **Cloudflare tunnel token**. Anyone holding it can run a
  second connector for this tunnel and receive a share of its traffic. Rotating
  the token is the only recovery.
* The box holds **DeepSeek and Telegram credentials** and the **OCI instance
  identity** (instance principal, scoped by policy to the snapshot bucket only).
* **No GitHub credential lives here.** CI keeps its deploy private key in GitHub
  secrets, so a compromised box cannot push to the repository.
* The rebuild path restores from the snapshot bucket, so a tampered snapshot
  would persist across rebuilds. `hermes-restore.sh` therefore refuses archives
  with absolute paths or `..` traversal, and extracts only into
  `/home/hermes/.hermes`.

If the agent is ever compromised: rotate the tunnel token, the Telegram bot
token and the DeepSeek key, then rebuild with `destroy_first`.

## Always Free compliance

| Component | Config | Always Free limit | Verdict |
|---|---|---|---|
| Compute | `VM.Standard.A1.Flex`, 2 OCPU / 12 GB | 1,500 OCPU-hrs + 9,000 GB-hrs/mo (= 2 OCPU / 12 GB continuous) | within |
| Block volume | boot volume 50 GB | 200 GB total (boot + block) | within |
| Object Storage | tfstate bucket + `hermes-backups` (a few MB per snapshot, 10 kept) | 20 GB | within |
| Networking | VCN, IGW, route table, subnet, 1 ephemeral public IP | all $0 | within |
| Image | Canonical Ubuntu 24.04 (aarch64) | Always Free-eligible platform image | within |

**Caveats**

* Oracle may **reclaim idle A1 instances** (CPU 95th pct <20%, network <20%, and —
  A1 only — memory <20% over 7 days). Keep the box busy.
* The tunnel token and the app secrets are injected via cloud-init, so they land
  in the OCI tfstate (private bucket) and in instance metadata (readable from the
  box itself). Both are scoped to this tenancy. Accepted trade-off.
* Running the agent as root-equivalent, with the dashboard exposed behind Access,
  means one prompt injection is host root. That is the deliberate trade for a box
  with nothing but Hermes on it.
* `user_data` runs on **first boot only**. Editing `cloud-init.yaml.tftpl` changes
  nothing on a running instance — use `destroy_first` to rebuild.
* OCI caps user data + metadata at **32,000 bytes**; the rendered payload is
  ~17.6 KB and `scripts/check-cloud-init.py` fails CI past the cap.

## Architecture

```
you / CI ── ssh.sreeramkr.com ──> Cloudflare Access ──> cloudflared (host, outbound)
                                                          └─> 127.0.0.1:22   sshd (ubuntu)

browser ── hermes.sreeramkr.com ─> Cloudflare Access ──> cloudflared
                                                          └─> 127.0.0.1:9119 hermes dashboard

Telegram <── long poll (outbound) ── hermes-gateway ──> api.deepseek.com

cron (6-hourly) ── hermes-backup.sh ──> OCI Object Storage bucket hermes-backups
```

* VCN `10.0.0.0/16`, public subnet `10.0.0.0/24`, IGW + default route
* No security group; `ufw` allows nothing in; both listeners bind loopback
* A1.Flex 2 OCPU / 12 GB, Ubuntu 24.04 aarch64, 50 GB boot, ephemeral public IP

## One-time setup

CI reads credentials from GitHub **Secrets / Variables**:

| Name | Kind | Used for |
|---|---|---|
| `OCI_API_KEY`, `OCI_USER_OCID`, `OCI_FINGERPRINT`, `OCI_TENANCY_OCID` | secret | Terraform + CLI auth |
| `OCI_SSH_PUBLIC_KEY` | variable | public half of the deploy key (injected into `ubuntu`) |
| `OCI_SSH_PRIVATE_KEY` | secret | private half, used by the workflow to reach the box |
| `OCI_TFSTATE_BUCKET` | variable | Terraform state bucket |
| `CLOUDFLARE_TUNNEL_TOKEN` | secret | the tunnel itself |
| `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET` | secret | Access service token for SSH |
| `DEEPSEEK_API_KEY`, `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS` | secret | Hermes |
| `HERMES_DASHBOARD_PASSWORD`, `HERMES_DASHBOARD_SECRET` | secret | dashboard auth (user `admin`; secret = `openssl rand -base64 32`) |

Tunnel routes (Cloudflare dashboard → Zero Trust → Networks → Tunnels):

1. `ssh.sreeramkr.com` → **SSH** `localhost:22` — Access app with two policies:
   your email, and a **Service Auth** rule for the CI service token.
2. `hermes.sreeramkr.com` → **HTTP** `localhost:9119` — Access app, same policies.
   Hermes' own username/password provider is the second layer.

Generate the deploy key once and keep the halves apart:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/oci-deploy -C oci-deploy   # private -> OCI_SSH_PRIVATE_KEY
cat ~/.ssh/oci-deploy.pub                                   # public  -> OCI_SSH_PUBLIC_KEY
```

## Deploy

Run **Actions → OCI Provision → Run workflow**. The workflow renders and validates
the cloud-init template first (`checks`: shell syntax, `terraform fmt`, render +
validate), then applies. On the rebuild path it also:

1. takes a **fresh snapshot** over SSH and refuses to continue if the bucket is empty,
2. destroys **only the instance** (`-target=oci_core_instance.portfolio_node`) so the
   bucket, dynamic group and policy survive,
3. waits for SSH and `/var/log/cloud_init_complete`,
4. runs `hermes-restore.sh true` and starts both units,
5. verifies units, dashboard status, listeners and the restored-state marker.

Two details worth knowing: a **targeted `terraform apply`** creates the snapshot
bucket, dynamic group and policy *before* the snapshot runs (the snapshot uploads
to that bucket), and a preflight check fails fast when Access rejects the service
token or when `OCI_SSH_PRIVATE_KEY` does not match `OCI_SSH_PUBLIC_KEY`. Use
`skip_snapshot: true` to rebuild when the old box is unreachable or has nothing
worth keeping — the new box then starts empty instead of blocking on the snapshot.

```bash
# from a laptop, with cloudflared installed and an Access login
ssh -o ProxyCommand="cloudflared access ssh --hostname %h" ubuntu@ssh.sreeramkr.com
```

## State snapshots

* `/etc/cron.d/hermes-backup` runs `hermes-backup.sh` every six hours: stop both
  units, tar `/home/hermes/.hermes` (excluding the re-clonable `hermes-agent`
  checkout), upload with the instance principal, prune to the newest 10, start.
* On the rebuild path, CI fetches the same tar over SSH and uploads it with its
  own OCI credentials before destroying anything, so a box whose cron or tooling
  is broken still gets a last backup.
* `hermes-restore.sh` installs the newest snapshot and writes a `.restored` marker,
  so it is safe to run on every deploy. `.env` always comes fresh from
  `/etc/hermes/hermes.env`; `config.yaml` comes from the snapshot (dashboard edits
  win over the repo baseline).
* Force a fresh snapshot before a rebuild you care about:
  `sudo /usr/local/sbin/hermes-backup.sh`.

## First migration from the Docker-era box (one time only)

The live box still runs the Docker-era layout and has no `sshd`, so CI cannot
reach it and the pre-destroy snapshot cannot run. Order matters here:

1. In the Cloudflare dashboard, point `ssh.sreeramkr.com` at **SSH**
   `localhost:22` and attach the Access app with the service-token policy.
2. From the existing ttyd terminal on the box, open the SSH path and move the
   agent's data into the native layout:

   ```bash
   sudo apt-get install -y openssh-server
   printf 'ListenAddress 127.0.0.1\nPasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\nAllowUsers ubuntu\nX11Forwarding no\n' \
     | sudo tee /etc/ssh/sshd_config.d/99-devbox.conf
   sudo systemctl restart ssh
   # The instance was built with the PREVIOUS OCI_SSH_PUBLIC_KEY, so a freshly
   # generated pair must be trusted here or CI cannot reach the box at all.
   # Paste the single line from your new oci_key.pub:
   echo 'ssh-ed25519 AAAA… oci-deploy' | sudo tee -a /home/ubuntu/.ssh/authorized_keys
   sudo mkdir -p /home/hermes
   sudo cp -a /opt/hermes /home/hermes/.hermes
   ```

3. Run **OCI Provision** with `destroy_first`. The snapshot now succeeds, and the
   rebuilt box restores it.

If the old state is not worth keeping, skip this and destroy the instance
directly (`terraform destroy -target=oci_core_instance.portfolio_node`); the
rebuild then starts empty.

## Verification

```bash
systemctl is-active hermes-gateway.service hermes-dashboard.service
curl -fsS http://127.0.0.1:9119/api/status        # auth_required / auth_providers
ss -ltn | grep -E ':(22|9119)\b'                  # loopback only
journalctl -u cloudflared --no-pager -n 50 | grep "Registered tunnel connection"
sudo test -f /home/hermes/.hermes/.restored && echo restored
tail -n 20 /var/log/hermes-backup.log
```

Emergency backdoor (tunnel or Access down): OCI serial console
(`Compute → instance → Resources → Console connection`).

## Maintenance

**Monthly, 5th at 03:05** (`/etc/cron.d/maintenance` → `maintenance.sh`):

1. `apt-get update && apt-get upgrade` — kernel, cloudflared.
2. As `hermes`: `hermes update` (brings Python, Node and the checkout forward, and
   rolls the checkout back if the pulled code does not parse).
3. Reboot.

Each step is logged and skipped on failure, so a bad step never blocks a later one
or the reboot. `hermes update` may skip its new-config prompt when it runs from
cron, so after a monthly pass run `hermes config check` over SSH — and
`hermes config migrate` if it lists missing options.

## Destroy

```bash
cd infra/oci && terraform destroy      # or run the workflow with destroy_first
```

The instance is disposable; the snapshot bucket is not. A full `terraform destroy`
deletes it, which is why the rebuild path targets the instance only.
