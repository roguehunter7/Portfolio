# infra/oci — Oracle Linux 10 dev box

Zero-ingress Oracle A1.Flex provisioned by GitHub Actions + Terraform. The VM has
**no public ports**: the NSG has zero ingress rules, `firewalld` allows nothing in,
and `sshd` is disabled at the end of provisioning. Everything reachable arrives over
the outbound Cloudflare Tunnel.

## Why Oracle Linux 10

* It is a first-class OCI platform image for Arm (`Oracle-Linux-10.2-aarch64`), with a
  support window to 2035 — Ubuntu 24.04 ends in 2029, and **Ubuntu 26.04 is not
  published on OCI at all**.
* Its appstream carries **nodejs 22.23.2**, above DeepSeek Harness's `^22.19.0` floor.
  Ubuntu 24.04 ships 18.19, which is why the previous design needed nvm. No nvm, no
  NodeSource here — Node is a dnf package that the monthly upgrade patches.
* The Oracle Cloud Agent ships as an rpm and Run Command is officially supported
  (on Ubuntu it is an unofficial snap).

## Workloads

| Workload | How it runs | Reachable at |
|---|---|---|
| Cloudflare Tunnel | `cloudflared.service`, outbound | the only ingress path |
| Browser terminal | `ttyd` + tmux, loopback `:7681`, user `opc` | `ssh.sreeramkr.com` |
| DeepSeek Harness | `dsh-web.service` (loopback `:3082`) behind the `dsh-full-remote` auth proxy (`:3080`) | `dsh.sreeramkr.com` |
| Hermes Agent | native install, systemd **user** service `hermes-gateway` for user `hermes` | Telegram (long poll outbound) |

There is **no container runtime** — no Docker, no podman. Hermes runs natively, which
also removes the SELinux volume-label and podman-conflict friction that containers
would bring on this distro.

## Always Free compliance

| Component | Config | Always Free limit | Verdict |
|---|---|---|---|
| Compute | `VM.Standard.A1.Flex`, 2 OCPU / 12 GB | 1,500 OCPU-hrs + 9,000 GB-hrs/mo (= 2 OCPU / 12 GB continuous) | ✅ within |
| Block volume | boot volume 50 GB | 200 GB total (boot + block) | ✅ within |
| Object Storage | tfstate bucket (KB-size) | 20 GB | ✅ within |
| Networking | VCN, IGW, route table, subnet, NSG, 1 ephemeral public IP | all $0 | ✅ within |
| Image | Oracle Linux 10 (aarch64) | Always Free-eligible platform image | ✅ within |

**Caveats**
- Oracle may **reclaim idle A1 instances** (CPU 95th pct <20%, network <20%, and — A1 only — memory <20% over 7 days). Keep the box busy.
- The tunnel token and the app secrets are injected via cloud-init, so they land in
  the OCI tfstate (private bucket) and in instance metadata (readable from the box
  itself). Both are scoped to this tenancy. Accepted trade-off.
- `user_data` runs on **first boot only**. Editing `cloud-init.yaml.tftpl` changes
  nothing on a running instance — use `destroy_first` to rebuild.
- OCI caps user data + metadata at **32,000 bytes**. The rendered payload is ~19 KB
  (scripts and configs are embedded `gz+b64`); `scripts/check-cloud-init.py` fails CI
  if that ever grows past the cap.

## Architecture

```
browser ── https://dsh.sreeramkr.com ─> Cloudflare edge ─> cloudflared (on VM, outbound)
                                                              └─> 127.0.0.1:3080  dsh-full-remote
                                                                    (login, device sessions, audit)
                                                                       └─> 127.0.0.1:3082  dsh web

browser ── https://ssh.sreeramkr.com ─> Cloudflare edge ─> cloudflared ─> 127.0.0.1:7681  ttyd -> tmux

Telegram  <── long poll (outbound) ── hermes-gateway ──> api.deepseek.com
```

- VCN `10.0.0.0/16`, public subnet `10.0.0.0/24`, IGW + default route
- NSG `instance-nsg`: **no rules** (= deny-all ingress); firewalld allows nothing in
- A1.Flex 2 OCPU / 12 GB, Oracle Linux 10 aarch64 (UEK R8), 50 GB boot, ephemeral public IP
- SELinux stays **enforcing** (no container labels needed, since there is no container runtime)

## Why DSH sits behind a proxy

`dsh web --trusted-host dsh.sreeramkr.com` opens the harness's Host/Origin fence to a
public hostname and leaves the per-process startup token as the only credential —
pasted into the URL after every restart. `dsh-full-remote` is placed in front instead:

- one login per device, 30-day session cookie — no token in the URL
- 192-bit access token in a `0600` state file (`~/.dsh/reverse-proxy.json`)
- audit log, login lockout, optional CIDR allowlist / first-visit approval
- Host/Origin rewritten back to loopback, so `settings.*`, `credentials.*` and
  `host.listDirectory` keep working remotely
- the harness port (`:3082`) is never exposed: if the proxy is down, `:3080` is simply
  closed (fail-closed), and the tunnel route does not change

## One-time setup

CI reads credentials from GitHub **Secrets / Variables** (names are in
`.github/workflows/oci-provision.yml`):

`OCI_API_KEY`, `OCI_USER_OCID`, `OCI_FINGERPRINT`, `OCI_TENANCY_OCID`,
`CLOUDFLARE_TUNNEL_TOKEN`, `TTYD_PASSWORD`, `DEEPSEEK_API_KEY`,
`TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USERS` (optional); variables:
`OCI_SSH_PUBLIC_KEY`, `OCI_TFSTATE_BUCKET`.

Tunnel routes (Cloudflare dashboard → Zero Trust → Networks → Tunnels):

1. `ssh.sreeramkr.com` → **HTTP** `localhost:7681` (ttyd)
2. `dsh.sreeramkr.com` → **HTTP** `localhost:3080` (the auth proxy)

## Deploy

Run **Actions → OCI Provision → Run workflow**. The workflow runs two guards first
(`checks`: shell syntax, `terraform fmt`, render + validate cloud-init; `deps`: install
the exact package set in an `oraclelinux:10` container), then applies. `destroy_first`
destroys the VM and re-applies, which is the only way to re-run cloud-init.

## Access

- **DSH:** open https://dsh.sreeramkr.com → login page. Read the access token once in
  the terminal: `jq -r .accessToken ~/.dsh/reverse-proxy.json`. One login per device.
- **Terminal:** https://ssh.sreeramkr.com → user `sreeram` + the `TTYD_PASSWORD`
  secret → tmux session `main`.
- **Hermes:** message the bot on Telegram. It cannot message you first — open the bot
  once and send `/start`. The setup log prints the bot username.

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
sudo -u hermes XDG_RUNTIME_DIR=/run/user/$(id -u hermes) systemctl --user status hermes-gateway
hermes doctor                                         # installed by the setup script
journalctl --user -u hermes-gateway -n 50 | grep -i telegram
```

## Hermes (native)

- Installed by the official installer as the `hermes` service user:
  `--skip-setup --skip-computer-use --non-interactive`. No container, no Docker.
- **Browser toolset works**, unlike a naive RPM install: `provision.sh` installs the
  Chromium system libraries (Playwright does not do that on RPM hosts), and the
  installer runs with `PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu24.04-arm64` because
  Playwright does not recognise Oracle Linux (`ID=ol`); OL10 is glibc 2.39, the same
  as that build.
- `--skip-computer-use` skips the `cua-driver` (GUI desktop control). This box is
  headless, so it would be a 660-second download with nothing to control.
- Gateway is a **user** service made boot-persistent by `loginctl enable-linger hermes`.
- Secrets and model config live in `~/.hermes/.env` (0600) and `~/.hermes/config.yaml`,
  written from `/etc/hermes/*` by cloud-init. Model routing: main loop
  `deepseek-v4-pro`, delegation and auxiliary tasks `deepseek-v4-flash`.
- **Telegram is verified at install time**: the script calls `getMe` (token valid),
  clears any webhook that would block long polling (`getWebhookInfo` / `deleteWebhook`),
  then checks the gateway is active and greps its log for Telegram errors.
- `/usr/local/bin/hermes` is a symlink to the venv launcher, so root and cron can call
  it (the repo script with system Python raises `ModuleNotFoundError: dotenv`).
- **Updates are manual**: `sudo -u hermes /usr/local/bin/hermes update` in the terminal.
  There is no automated Hermes update — it moves on rebuild or when you run it.

## DeepSeek Harness

- `dsh-web.service` runs `dsh web --port 3082 --no-open` as `opc` (`Restart=always`).
- Node comes from dnf (appstream 22.23.2); npm installs the newest published
  `@deepseek-ai/dsh` (publish-ordered `versions` list, channel-agnostic) into
  `~/.npm-global` as `opc`, never as root — DSH's dependency tree compiles `node-pty`
  and `koffi`, and running install scripts as root is the `sudo npm install` trap.
  npm 10 (bundled with Node 22) has no `allow-scripts` gate, so the allowlist is seeded
  only when npm is new enough to honour it.
- `scripts/dsh-setup.sh` is idempotent: install, plugin, proxy state, unit, restart.
- The LLM key is in `/etc/dsh-web.env` (`EnvironmentFile`); the credentials provider
  ranks the inherited environment above `~/.dsh/.credentials.yaml`.

### Migrating a box that runs dsh by hand

```bash
tmux kill-session -t main          # stops the hand-run process (drops the GUI session)
sudo bash ~/Portfolio/scripts/dsh-setup.sh
```

## Maintenance — two cadences

**Monthly, 5th at 03:05** (`/etc/cron.d/maintenance`, one line, mirrors the
Vaultwarden host): `dnf -y upgrade ; systemctl reboot`. Covers the kernel, Node,
cloudflared, ttyd, ripgrep, htop, gh — everything from the repos. `;` separators on
purpose: a failed upgrade must not skip the reboot. Every workload is supervised, so
the reboot costs ~30 seconds.

**Weekly, Sunday at 02:05** (`/etc/cron.d/dsh-update` →
`/usr/local/sbin/dsh-update.sh`): install the newest published `@deepseek-ai/dsh` +
plugin refresh + `systemctl restart dsh-web`. One hour before the monthly window, so a reboot
can never land mid-update. No health check and no rollback by design: if a bad alpha
lands, the box is still reachable through ttyd and `journalctl -u dsh-web` says why.

## Destroy

```bash
cd infra/oci && terraform destroy      # or run the workflow with destroy_first
```