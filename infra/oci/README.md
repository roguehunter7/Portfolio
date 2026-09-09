# infra/oci — Oracle Cloud dev box (Phase 8+)

Zero-ingress Oracle A1.Flex provisioned by GitHub Actions + Terraform. The VM has
**no public ports**: the NSG has zero ingress rules, `ufw` denies incoming, and
`sshd` is disabled at the end of provisioning. Everything reachable arrives over
the outbound Cloudflare Tunnel.

## Workloads

| Workload | How it runs | Reachable at |
|---|---|---|
| Cloudflare Tunnel | `cloudflared.service`, outbound | the only ingress path |
| Browser terminal | `ttyd` + tmux, loopback `:7681` | `ssh.sreeramkr.com` |
| DeepSeek Harness | `dsh-web.service` (loopback `:3082`) behind the `dsh-full-remote` auth proxy (`:3080`) | `dsh.sreeramkr.com` |
| Hermes Agent | Docker container from the official image, no published port | Telegram (long poll outbound) |

## Always Free compliance (verified against official docs, 2026-08)

| Component | Config | Always Free limit | Verdict |
|---|---|---|---|
| Compute | `VM.Standard.A1.Flex`, 2 OCPU / 12 GB | 1,500 OCPU-hrs + 9,000 GB-hrs/mo (= 2 OCPU / 12 GB continuous; Oracle halved the old 4/24 in June 2026) | ✅ within |
| Block volume | boot volume 50 GB | 200 GB total (boot + block) | ✅ within |
| Object Storage | tfstate bucket (KB-size) | 20 GB | ✅ within |
| Networking | VCN, IGW, route table, subnet, NSG, 1 ephemeral public IP | all $0; no NAT gateway used | ✅ within |
| SSH transport | none — `sshd` disabled; admin is the browser terminal | — | ✅ |
| Image | Canonical Ubuntu 24.04 (ARM64) | Always Free-eligible platform image, no license fee | ✅ within |
| Egress | 10 TB/mo outbound | not approached | ✅ |

**Caveats**
- Oracle may **reclaim idle A1 instances** (CPU 95th pct <20%, network <20%, and — A1 only — memory <20% over 7 days). Keep the box busy.
- The tunnel token and the Hermes secrets are injected via cloud-init, so they land in
  the OCI tfstate (private bucket) and in instance metadata (readable from the box
  itself). Both are scoped to this tenancy; neither can manage OCI. Accepted trade-off.
- `user_data` is only executed on **first boot**. Editing `cloud-init.yaml.tftpl` changes
  nothing on a running instance — use `destroy_first` to rebuild.

## Architecture

```
browser ── https://dsh.sreeramkr.com ─> Cloudflare edge ─> cloudflared (on VM, outbound)
                                                              └─> 127.0.0.1:3080  dsh-full-remote
                                                                    (login, device sessions, audit)
                                                                       └─> 127.0.0.1:3082  dsh web

browser ── https://ssh.sreeramkr.com ─> Cloudflare edge ─> cloudflared ─> 127.0.0.1:7681  ttyd -> tmux

Telegram  <── long poll (outbound) ── hermes container ──> api.deepseek.com
```

- VCN `10.0.0.0/16`, public subnet `10.0.0.0/24`, IGW + default route
- NSG `instance-nsg`: **no rules** (= deny-all ingress)
- A1.Flex 2 OCPU / 12 GB, Ubuntu 24.04 ARM64, 50 GB boot, ephemeral public IP (egress only)
- cloud-init: cloudflared + nvm/Node LTS + repo checkout, Docker Engine + compose,
  the Hermes stack, `dsh-web` + its auth proxy, weekly maintenance, then hardening

## Why DSH sits behind a proxy

`dsh web --trusted-host dsh.sreeramkr.com` opens the harness's Host/Origin fence to a
public hostname and leaves the per-process startup token as the only credential —
which then has to be pasted into the URL after every restart. `dsh-full-remote` is
placed in front instead:

- one login per device, 30-day session cookie — no token in the URL, ever
- 192-bit access token in a `0600` state file (`~/.dsh/reverse-proxy.json`)
- audit log, login lockout, optional CIDR allowlist / first-visit approval
- Host/Origin rewritten back to loopback, so `settings.*`, `credentials.*` and
  `host.listDirectory` keep working remotely
- the harness port (`:3082`) is never exposed: if the proxy is down, `:3080` is
  simply closed (fail-closed), and the tunnel route does not change

## One-time setup (Console)

CI reads credentials from GitHub **Secrets / Variables** (exact names are in
`.github/workflows/oci-provision.yml`). Required secrets:

`OCI_API_KEY`, `OCI_USER_OCID`, `OCI_FINGERPRINT`, `OCI_TENANCY_OCID`,
`CLOUDFLARE_TUNNEL_TOKEN`, `TTYD_PASSWORD`, `DEEPSEEK_API_KEY`,
`TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS` (optional); variables:
`OCI_SSH_PUBLIC_KEY`, `OCI_TFSTATE_BUCKET`.

Tunnel routes (Cloudflare dashboard → Zero Trust → Networks → Tunnels):

1. `ssh.sreeramkr.com` → **HTTP** `localhost:7681` (ttyd)
2. `dsh.sreeramkr.com` → **HTTP** `localhost:3080` (the auth proxy)

## Deploy

Run **Actions → OCI Provision → Run workflow**. `destroy_first` destroys the VM and
re-applies, which is the only way to re-run cloud-init.

## Access

- **DSH:** open https://dsh.sreeramkr.com → login page. The access token is in the
  state file; read it once in the terminal:
  `jq -r .accessToken ~/.dsh/reverse-proxy.json`
  Log in once per device — the session cookie lasts 30 days.
- **Terminal:** https://ssh.sreeramkr.com → user `sreeram` + the `TTYD_PASSWORD`
  secret → tmux session `main`.
- **Hermes:** message the bot on Telegram. Nothing to open.

Emergency backdoor (tunnel down): OCI serial console
(`Compute → instance → Resources → Console connection`).

## Verifying (CI cannot reach the box)

Zero ingress means the workflow can only apply. Verification happens in the browser
terminal:

```bash
ls /var/log/cloud_init_complete                       # cloud-init ran to the end
systemctl status dsh-web --no-pager                   # harness service
curl -fsS http://127.0.0.1:3080/_dsh_reverse_proxy/healthz   # auth proxy
jq -r .accessToken ~/.dsh/reverse-proxy.json          # DSH login token
docker compose -f /opt/hermes/docker-compose.yml ps   # Hermes container
docker logs hermes --tail 40                          # gateway + Telegram
curl -fsS http://127.0.0.1:8642/healthz || true       # Hermes health (loopback)
```

## Hermes

- Official image `nousresearch/hermes-agent` (arm64 manifest), pinned in
  `infra/hermes/docker-compose.yml`. Everything Hermes needs — Python, Node,
  Chromium — lives in the image, so the host gains nothing but the container runtime.
- Model routing (`infra/hermes/config.yaml`): the main loop runs
  `deepseek-v4-pro`; delegation and every auxiliary task run
  `deepseek-v4-flash`.
- `/opt/hermes` is mounted at `/opt/data` (config, sessions, skills, memories).
  Updating = `docker compose pull && docker compose up -d`; `hermes update` is not
  supported inside Docker by design.
- Secrets are written to `/opt/hermes/.env` (root-owned `0600`) by cloud-init.
- `restart: unless-stopped` + the s6-supervised gateway means the Monday 02:00
  maintenance reboot brings the assistant back on its own.

## DeepSeek Harness

- `dsh-web.service` runs `dsh web --port 3082 --no-open` as `ubuntu`
  (`Restart=always`, so a crash or reboot no longer takes the URL down).
- `scripts/dsh-setup.sh` is idempotent: it installs DSH, adds the plugin, seeds the
  proxy state, and rewrites the unit. Re-run it after `nvm install --lts`, because
  the unit's `PATH` carries the Node bin directory resolved at setup time.
- The harness's LLM key is provisioned in `/etc/dsh-web.env` (root-owned `0600`).
  The credentials provider layers the inherited environment **above**
  `~/.dsh/.credentials.yaml`, so a rebuilt box works without a manual key entry.
  To rotate it: update the `DEEPSEEK_API_KEY` secret and rebuild, or edit that
  file and `systemctl restart dsh-web`.

### Migrating a box that still runs dsh by hand

The first build ran `dsh web` manually inside tmux, which is why the URL died on
every restart and needed the token pasted again. To adopt the service on a running
box **without** rebuilding (this stops the hand-run process, so it drops any open
GUI session):

```bash
tmux kill-session -t main
sudo bash ~/Portfolio/scripts/dsh-setup.sh
```

## Destroy

```bash
cd infra/oci && terraform destroy      # or run the workflow with destroy_first
```
