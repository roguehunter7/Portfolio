# infra/oci — Ubuntu 24.04 dev box

Zero-ingress Oracle A1.Flex provisioned by GitHub Actions + Terraform. The VM has
**no public ports**: the NSG has zero ingress rules, `ufw` allows nothing in,
and `sshd` is disabled at the end of provisioning. Everything reachable arrives over
the outbound Cloudflare Tunnel.

## Why Ubuntu 24.04

* It is a first-class OCI platform image for Arm (`Canonical Ubuntu 24.04`), with the
  default `ubuntu` user and native `apt`/`ufw` tooling that the provisioning
  scripts are written against.
* Node is **not** an apt package here. The interactive user (`ubuntu`) gets Node via
  **nvm** (the official installer); Hermes runs in the official image and carries
  its own Node/Python/Chromium, so a monthly Node bump can never touch the gateway.

## Workloads

| Workload | How it runs | Reachable at |
|---|---|---|
| Cloudflare Tunnel | `cloudflared.service`, outbound | the only ingress path |
| Browser terminal | `ttyd` + tmux, loopback `:7681`, user `ubuntu` | `ssh.sreeramkr.com` |
| DeepSeek Harness | installed by hand as `ubuntu` (nvm); **run on demand** from the terminal; `dsh web` loopback `:3080` | `dsh.sreeramkr.com` |
| Hermes Agent | Docker container from the official image; loopback API only | Telegram (long poll outbound) |

Docker runs **only Hermes**: the official image carries its own Python/Node/Chromium,
so the host gets no Hermes toolchain and the agent never reads the host's credentials
(`~/.dsh`, `~/.config/gh`, the repo).

## Always Free compliance

| Component | Config | Always Free limit | Verdict |
|---|---|---|---|
| Compute | `VM.Standard.A1.Flex`, 2 OCPU / 12 GB | 1,500 OCPU-hrs + 9,000 GB-hrs/mo (= 2 OCPU / 12 GB continuous) | within |
| Block volume | boot volume 50 GB | 200 GB total (boot + block) | within |
| Object Storage | tfstate bucket (KB-size) | 20 GB | within |
| Networking | VCN, IGW, route table, subnet, NSG, 1 ephemeral public IP | all $0 | within |
| Image | Canonical Ubuntu 24.04 (aarch64) | Always Free-eligible platform image | within |

**Caveats**
- Oracle may **reclaim idle A1 instances** (CPU 95th pct <20%, network <20%, and — A1 only — memory <20% over 7 days). Keep the box busy.
- The tunnel token and the app secrets are injected via cloud-init, so they land in
  the OCI tfstate (private bucket) and in instance metadata (readable from the box
  itself). Both are scoped to this tenancy. Accepted trade-off.
- `user_data` runs on **first boot only**. Editing `cloud-init.yaml.tftpl` changes
  nothing on a running instance — use `destroy_first` to rebuild.
- OCI caps user data + metadata at **32,000 bytes**. The rendered payload is ~14 KB
  (scripts and configs are embedded `gz+b64`); `scripts/check-cloud-init.py` fails CI
  if that ever grows past the cap.

## Architecture

```
browser ── https://dsh.sreeramkr.com ─> Cloudflare edge ─> cloudflared (on VM, outbound)
                                                              └─> 127.0.0.1:3080  dsh web
                                                                  (run on demand from ttyd)

browser ── https://ssh.sreeramkr.com ─> Cloudflare edge ─> cloudflared ─> 127.0.0.1:7681  ttyd -> tmux

Telegram  <── long poll (outbound) ── Hermes container ──> api.deepseek.com
```

- VCN `10.0.0.0/16`, public subnet `10.0.0.0/24`, IGW + default route
- NSG `instance-nsg`: **no rules** (= deny-all ingress); ufw allows nothing in
- A1.Flex 2 OCPU / 12 GB, Ubuntu 24.04 aarch64, 50 GB boot, ephemeral public IP
- ufw: default deny incoming, allow outgoing; all published ports bound to loopback

## One-time setup

CI reads credentials from GitHub **Secrets / Variables** (names are in
`.github/workflows/oci-provision.yml`):

`OCI_API_KEY`, `OCI_USER_OCID`, `OCI_FINGERPRINT`, `OCI_TENANCY_OCID`,
`CLOUDFLARE_TUNNEL_TOKEN`, `TTYD_PASSWORD`, `DEEPSEEK_API_KEY`,
`TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS` (optional); variables:
`OCI_SSH_PUBLIC_KEY`, `OCI_TFSTATE_BUCKET`.

Tunnel routes (Cloudflare dashboard → Zero Trust → Networks → Tunnels):

1. `ssh.sreeramkr.com` → **HTTP** `127.0.0.1:7681` (ttyd)
2. `dsh.sreeramkr.com` → **HTTP** `127.0.0.1:3080` (dsh web)

Either `127.0.0.1` or `localhost` works. cloudflared is a Go program, and Go
resolves `localhost` to both `::1` and `127.0.0.1` and falls back to whichever
answers, so a service bound to IPv4 loopback is reached either way. What matters
is that the origin port matches the service's listening port and the service
binds loopback only.

## Deploy

Run **Actions → OCI Provision → Run workflow**. The workflow renders and validates
the cloud-init template first (`checks`: shell syntax, `terraform fmt`, render +
validate), then applies. `destroy_first` destroys the VM and re-applies, which is
the only way to re-run cloud-init.

First boot is ordered for fast access: cloudflared and ttyd come up first
(~2–3 min), then the full `apt upgrade`, nvm/Node and Hermes. So
`ssh.sreeramkr.com` is usable long before `/var/log/cloud_init_complete`
appears.

## Access

- **Terminal:** https://ssh.sreeramkr.com → user `sreeram` + the `TTYD_PASSWORD`
  secret → tmux session `main`.
- **DSH (on demand):** in the terminal, `dsh web --trusted-host dsh.sreeramkr.com`,
  then open https://dsh.sreeramkr.com and paste the token the harness prints. The
  login shell already exports `DEEPSEEK_API_KEY` from `~/.dsh/env`. Run it inside
  tmux so it survives closing the browser tab.
- **Hermes:** message the bot on Telegram. It cannot message you first — open the bot
  once and send `/start`.

Emergency backdoor (tunnel down): OCI serial console
(`Compute → instance → Resources → Console connection`).

## Verifying (CI cannot reach the box)

Zero ingress means the workflow can only apply. Verification happens in the browser
terminal:

```bash
ls /var/log/cloud_init_complete                 # cloud-init ran to the end
systemctl status cloudflared ttyd --no-pager     # the two system services
command -v node && node -v                       # nvm toolchain (dsh is installed by hand)
ss -ltnp | grep -E '7681|3080'                    # ttyd; :3080 only while dsh runs
docker compose -f /opt/hermes/docker-compose.yml ps   # Hermes container
docker logs hermes --tail 40 | grep -i telegram       # gateway + Telegram
curl -fsS http://127.0.0.1:8642/healthz || true       # Hermes health (loopback)
```

## Hermes (Docker)

- Official image `nousresearch/hermes-agent:latest`, `gateway run`,
  `restart: unless-stopped` (`infra/hermes/docker-compose.yml`). Everything Hermes
  needs — Python, Node, Chromium — lives in the image, so the host gains only the
  Docker runtime. The monthly maintenance job pulls new releases.
- `/opt/hermes` is mounted at `/opt/data` (config, sessions, skills, memories).
  Updating means `docker compose pull && up -d`; `hermes update` is not supported
  inside Docker by design.
- Secrets and model config: cloud-init stages `/etc/hermes/hermes.env` (0600) and
  `/etc/hermes/config.yaml`; `provision.sh` installs them as `/opt/hermes/.env`
  (0600) and `/opt/hermes/config.yaml`. Model routing: every call — main loop,
  delegation and auxiliary tasks — runs `deepseek-flash`.
- No port is published to the network: Telegram is long-polled outbound, and the
  gateway's API/dashboard on `:8642` is bound to loopback only. The agent is not
  reachable from the internet even if the rest of the box is.
- The gateway is s6-supervised inside the container, so a crash is restarted
  without losing the container; a reboot brings it back via `restart: unless-stopped`.

## DeepSeek Harness

- **Not installed by `provision.sh`** (deliberately). Install it as `ubuntu` into
  nvm's global tree, then run it from the terminal when you need it
  (`dsh web --trusted-host dsh.sreeramkr.com`, loopback `:3080`), inside tmux so
  it outlives the browser tab.
- No reverse-proxy plugin: the tunnel points straight at `:3080`, so the harness
  startup token is the credential and is pasted into the URL after a restart.
- `npm install -g` runs as `ubuntu`, never as root — DSH's dependency tree compiles
  `node-pty` and `koffi`, and running install scripts as root is the
  `sudo npm install` trap. On npm 11+, seed the install-script allowlist in
  `~/.npmrc` first: `allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs`.
- The LLM key is staged at `/etc/dsh/env` (0600 root) and installed to
  `~/.dsh/env` (0600 `ubuntu`); the login shell exports it.

## Maintenance — one cadence

**Monthly, 5th at 03:05** (`/etc/cron.d/maintenance` →
`/usr/local/sbin/maintenance.sh`): one pass that runs, in order,

1. `apt-get update && apt-get upgrade` — kernel, cloudflared, ttyd, ripgrep, htop, gh.
2. As `ubuntu`: re-run the nvm installer (newest nvm tag), `nvm install --lts`,
   `nvm install-latest-npm`, repoint `~/.nvm/current`.
3. Pull and recreate the Hermes container — `docker compose -f /opt/hermes/docker-compose.yml pull --quiet` then `up -d`; it follows `:latest`.

Then it reboots, and every supervised service plus the Hermes container comes
back. Each step is logged and skipped on failure, so a bad step never blocks a
later one or the reboot. DSH is intentionally **not** installed or updated by
these scripts; install and update it by hand.

## Destroy

```bash
cd infra/oci && terraform destroy      # or run the workflow with destroy_first
```
