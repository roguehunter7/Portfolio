# infra/oci — Oracle Linux 10 dev box

Zero-ingress Oracle A1.Flex provisioned by GitHub Actions + Terraform. The VM has
**no public ports**: the NSG has zero ingress rules, `firewalld` allows nothing in,
and `sshd` is disabled at the end of provisioning. Everything reachable arrives over
the outbound Cloudflare Tunnel.

## Why Oracle Linux 10

* It is a first-class OCI platform image for Arm (`Oracle-Linux-10.2-aarch64`), with a
  support window to 2035 — Ubuntu 24.04 ends in 2029, and **Ubuntu 26.04 is not
  published on OCI at all**.
* Node is **not** a dnf package here. The interactive user (`opc`) gets Node via
  **nvm** (the official installer; Oracle Linux ships no `nvm` package), and the
  Hermes gateway provisions its **own managed tree** (`~/.hermes/node`). Two trees,
  each updated by its own tool, so a monthly Node bump can never break the gateway
  unit that depends on it.
* The Oracle Cloud Agent ships as an rpm and Run Command is officially supported
  (on Ubuntu it is an unofficial snap).

## Workloads

| Workload | How it runs | Reachable at |
|---|---|---|
| Cloudflare Tunnel | `cloudflared.service`, outbound | the only ingress path |
| Browser terminal | `ttyd` + tmux, loopback `:7681`, user `opc` | `ssh.sreeramkr.com` |
| DeepSeek Harness | installed as `opc`, **run on demand** from the terminal; `dsh web` loopback `:3080` | `dsh.sreeramkr.com` |
| Hermes Agent | native install, systemd **user** service `hermes-gateway` for user `opc` | Telegram (long poll outbound) |

There is **no container runtime** — no Docker, no podman. Hermes runs natively, which
also removes the SELinux volume-label and podman-conflict friction that containers
would bring on this distro.

## Always Free compliance

| Component | Config | Always Free limit | Verdict |
|---|---|---|---|
| Compute | `VM.Standard.A1.Flex`, 2 OCPU / 12 GB | 1,500 OCPU-hrs + 9,000 GB-hrs/mo (= 2 OCPU / 12 GB continuous) | within |
| Block volume | boot volume 50 GB | 200 GB total (boot + block) | within |
| Object Storage | tfstate bucket (KB-size) | 20 GB | within |
| Networking | VCN, IGW, route table, subnet, NSG, 1 ephemeral public IP | all $0 | within |
| Image | Oracle Linux 10 (aarch64) | Always Free-eligible platform image | within |

**Caveats**
- Oracle may **reclaim idle A1 instances** (CPU 95th pct <20%, network <20%, and — A1 only — memory <20% over 7 days). Keep the box busy.
- The tunnel token and the app secrets are injected via cloud-init, so they land in
  the OCI tfstate (private bucket) and in instance metadata (readable from the box
  itself). Both are scoped to this tenancy. Accepted trade-off.
- `user_data` runs on **first boot only**. Editing `cloud-init.yaml.tftpl` changes
  nothing on a running instance — use `destroy_first` to rebuild.
- OCI caps user data + metadata at **32,000 bytes**. The rendered payload is ~17 KB
  (scripts and configs are embedded `gz+b64`); `scripts/check-cloud-init.py` fails CI
  if that ever grows past the cap.

## Architecture

```
browser ── https://dsh.sreeramkr.com ─> Cloudflare edge ─> cloudflared (on VM, outbound)
                                                              └─> 127.0.0.1:3080  dsh web
                                                                  (run on demand from ttyd)

browser ── https://ssh.sreeramkr.com ─> Cloudflare edge ─> cloudflared ─> 127.0.0.1:7681  ttyd -> tmux

Telegram  <── long poll (outbound) ── hermes-gateway ──> api.deepseek.com
```

- VCN `10.0.0.0/16`, public subnet `10.0.0.0/24`, IGW + default route
- NSG `instance-nsg`: **no rules** (= deny-all ingress); firewalld allows nothing in
- A1.Flex 2 OCPU / 12 GB, Oracle Linux 10 aarch64 (UEK R8), 50 GB boot, ephemeral public IP
- SELinux stays **enforcing** (no container labels needed, since there is no container runtime)

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

**Use the literal `127.0.0.1`, never `localhost`.** cloudflared resolves
`localhost` to `::1` (IPv6) on most modern Linux distros; both origins bind
IPv4 loopback only, so the tunnel gets `dial tcp [::1]:PORT: connection refused`
and Cloudflare returns a generic **502** for *both* hostnames even when the
services are healthy.

## Deploy

Run **Actions → OCI Provision → Run workflow**. The workflow runs two guards first
(`checks`: shell syntax, `terraform fmt`, render + validate cloud-init; `deps`: install
the exact package set in an `oraclelinux:10` container), then applies. `destroy_first`
destroys the VM and re-applies, which is the only way to re-run cloud-init.

## Access

- **Terminal:** https://ssh.sreeramkr.com → user `sreeram` + the `TTYD_PASSWORD`
  secret → tmux session `main`.
- **DSH (on demand):** in the terminal, `dsh web --trusted-host dsh.sreeramkr.com`,
  then open https://dsh.sreeramkr.com and paste the token the harness prints. The
  login shell already exports `DEEPSEEK_API_KEY` from `~/.dsh/env`. Run it inside
  tmux so it survives closing the browser tab.
- **Hermes:** message the bot on Telegram. It cannot message you first — open the bot
  once and send `/start`. The setup log prints the bot username.

Emergency backdoor (tunnel down): OCI serial console
(`Compute → instance → Resources → Console connection`).

## Verifying (CI cannot reach the box)

Zero ingress means the workflow can only apply. Verification happens in the browser
terminal:

```bash
ls /var/log/cloud_init_complete                 # cloud-init ran to the end
systemctl status cloudflared ttyd --no-pager     # the two system services
command -v node && node -v && dsh --version      # nvm toolchain + harness
ss -ltnp | grep -E '7681|3080'                    # ttyd; :3080 only while dsh runs
systemctl --user status hermes-gateway           # always-on Hermes gateway
journalctl --user -u hermes-gateway -n 50 | grep -i telegram
```

## Hermes (native)

- Installed by the official installer as `opc`:
  `--skip-setup --skip-computer-use --non-interactive`. No container, no Docker.
- **Browser toolset works**, unlike a naive RPM install: `provision.sh` installs the
  Chromium system libraries (Playwright does not do that on RPM hosts), and the
  installer runs with `PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu24.04-arm64` because
  Playwright does not recognise Oracle Linux (`ID=ol`); OL10 is glibc 2.39, the same
  as that build.
- `--skip-computer-use` skips the `cua-driver` (GUI desktop control). This box is
  headless, so it would be a 660-second download with nothing to control.
- The installer runs with `PATH=/usr/bin:/bin` on purpose: with nvm off PATH it
  provisions its own managed Node under `~/.hermes/node`, so the gateway unit does
  not depend on nvm's Node.
- Gateway is a **user** service made boot-persistent by `loginctl enable-linger opc`.
- Secrets and model config live in `~/.hermes/.env` (0600) and `~/.hermes/config.yaml`,
  written from `/etc/hermes/*` by cloud-init. Model routing: every call —
  main loop, delegation and auxiliary tasks — runs `deepseek-flash`.
- **Telegram is verified at install time**: the script calls `getMe` (token valid),
  clears any webhook that would block long polling (`getWebhookInfo` / `deleteWebhook`),
  then checks the gateway is active and greps its log for Telegram errors.

## DeepSeek Harness

- Installed as `opc` into nvm's global tree; **no systemd service**. Run it from the
  terminal when you need it (`dsh web --trusted-host dsh.sreeramkr.com`, loopback
  `:3080`), inside tmux so it outlives the browser tab.
- No reverse-proxy plugin: the tunnel points straight at `:3080`, so the harness
  startup token is the credential and is pasted into the URL after a restart.
- `npm install -g` runs as `opc`, never as root — DSH's dependency tree compiles
  `node-pty` and `koffi`, and running install scripts as root is the
  `sudo npm install` trap. npm 11+ gates install scripts behind `allow-scripts`;
  `provision.sh` seeds the allowlist only when npm is new enough to honour it.
- The LLM key is staged at `/etc/dsh/env` (0600 root) and installed to
  `~/.dsh/env` (0600 `opc`); the login shell exports it.

## Maintenance — one cadence

**Monthly, 5th at 03:05** (`/etc/cron.d/maintenance` →
`/usr/local/sbin/maintenance.sh`): one pass that runs, in order,

1. `dnf -y upgrade` — kernel, cloudflared, ttyd, ripgrep, htop, gh.
2. As `opc`: re-run the nvm installer (newest nvm tag), `nvm install --lts`,
   `nvm install-latest-npm`, repoint `~/.nvm/current`, then install the newest
   published `@deepseek-ai/dsh`.
3. As `opc`: `hermes update` — repo, Python deps and its managed Node tree.

Then it reboots, and every supervised/lingered unit comes back. Each step is
logged and skipped on failure, so a bad step never blocks a later one or the
reboot. There is no separate DSH cron: the harness is on-demand, so content
updates ride this cadence.

## Destroy

```bash
cd infra/oci && terraform destroy      # or run the workflow with destroy_first
```
