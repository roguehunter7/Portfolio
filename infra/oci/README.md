# infra/oci — Ubuntu 24.04 dev box

No-open-ports Oracle A1.Flex provisioned by GitHub Actions + Terraform. The VM has
**no open ports**: `ufw` allows nothing in, the OpenSSH server is removed at the
end of provisioning, and no service binds a public interface. Everything
reachable arrives over the outbound Cloudflare Tunnel.

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
| Browser terminal | `ttyd` + bash, loopback `:7681`, user `ubuntu` | `ssh.sreeramkr.com` |
| DeepSeek Harness | installed at first boot as `ubuntu` (nvm): pnpm, the `dsh` launcher and the `tui` profile; **run on demand** from the terminal; `dsh web` loopback `:3080` | `dsh.sreeramkr.com` |
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
| Networking | VCN, IGW, route table, subnet, 1 ephemeral public IP | all $0 | within |
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

browser ── https://ssh.sreeramkr.com ─> Cloudflare edge ─> cloudflared ─> 127.0.0.1:7681  ttyd -> bash

Telegram  <── long poll (outbound) ── Hermes container ──> api.deepseek.com
```

- VCN `10.0.0.0/16`, public subnet `10.0.0.0/24`, IGW + default route
- No security group; `ufw` allows nothing in and no service binds a public interface
- A1.Flex 2 OCPU / 12 GB, Ubuntu 24.04 aarch64, 50 GB boot, ephemeral public IP
- ufw: default deny incoming, allow outgoing; all published ports bound to loopback

## One-time setup

CI reads credentials from GitHub **Secrets / Variables** (names are in
`.github/workflows/oci-provision.yml`):

`OCI_API_KEY`, `OCI_USER_OCID`, `OCI_FINGERPRINT`, `OCI_TENANCY_OCID`,
`CLOUDFLARE_TUNNEL_TOKEN`, `DEEPSEEK_API_KEY`,
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

- **Terminal:** https://ssh.sreeramkr.com → a bash login shell. Access is gated by
  **Cloudflare Access** in front of the tunnel route; ttyd itself has no
  credential. History scrolls with the mouse wheel (xterm.js in the browser);
  Shift+wheel if a TUI has grabbed the mouse.
- **dsh-tui (on demand):** `provision.sh` already installed it
  (`dsh plugin --profile tui add @tomowang/dsh-tui`), so at the prompt just run
  `dsh --profile tui` (or `--resume` to reopen a session). It outlives the
  browser tab, but a ttyd restart or reboot ends the shell — `--resume` picks the
  session back up.
- **dsh web (on demand):** `dsh web --trusted-host dsh.sreeramkr.com`, then open
  https://dsh.sreeramkr.com and paste the token the harness prints. The login
  shell already exports `DEEPSEEK_API_KEY` from `~/.dsh/env`.
- **From a phone:** the grid autoscales (FitAddon → RESIZE_TERMINAL → PTY), but the
  soft keyboard has no Esc, Ctrl or arrows, so dsh-tui's modal input is unusable
  there. Use the DSH web UI (responsive) on a phone.
- **Hermes:** message the bot on Telegram. It cannot message you first — open the bot
  once and send `/start`.

Emergency backdoor (tunnel down): OCI serial console
(`Compute → instance → Resources → Console connection`).

## Browser terminal — scrollback model

`ttyd` owns the PTY and pumps bytes to xterm.js in the browser, which is where the
terminal — and its history — actually lives. There is no multiplexer in the chain:
bash is the child, and nothing intercepts the wheel. `tmux` was removed because
its `mouse on` default binds WheelUp to copy-mode, so scrolls ran in a buffer the
browser could not see; tmux did survive a ttyd restart, which plain bash does not.

Two consequences worth knowing:

- Shell history (prompts, command output) accumulates in xterm.js and scrolls with
  the wheel; the cap is xterm's default 1000 lines, so old lines age out rather than
  surviving until `clear`.
- `dsh-tui` runs `fullscreen: true`, i.e. the alternate screen, which has no
  scrollback of its own. Its transcript scrolls in-app (wheel, scrollbar gutter) and
  is not written to browser history. To read turns back later, use the in-app scroll,
  or `dsh --profile tui --resume` for the session itself.
- If a full-screen TUI ever grabs the mouse, Shift+wheel still reaches xterm.js.

## Verifying (CI cannot reach the box)

No open ports means the workflow can only apply. Verification happens in the browser
terminal:

```bash
ls /var/log/cloud_init_complete                 # cloud-init ran to the end
systemctl status cloudflared ttyd --no-pager     # the two system services
command -v node && node -v                       # nvm toolchain
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

- **Installed by `provision.sh`** as `ubuntu` into nvm's global tree: `pnpm`,
  then `npm install -g @deepseek-ai/dsh@next`, then two bundles:
  `dsh plugin --profile tui add @tomowang/dsh-tui` (terminal front door) and
  `dsh plugin --profile web add @tt-a1i/archify-dsh` (Skill-only bundle adding the
  Archify architecture-diagram skill to the web profile). Each command creates its
  profile on first use (`~/.dsh/profiles/tui`, `…/web`) and resolves the newest
  published version; nothing here is version-pinned. `pnpm` is required, not
  optional: `dsh plugin` is a pnpm forwarder and exits 127 without it. Run on
  demand (`dsh --profile tui`, loopback terminal; `dsh web --trusted-host
  dsh.sreeramkr.com`, loopback `:3080`, browser UI). ttyd keeps the process alive
  when the browser tab closes; a reboot ends it.
- No reverse-proxy plugin: the tunnel points straight at `:3080`, so the harness
  startup token is the credential and is pasted into the URL after a restart.
- `npm install -g` runs as `ubuntu`, never as root — DSH's dependency tree compiles
  `node-pty` and `koffi`, and running install scripts as root is the
  `sudo npm install` trap. On npm 11+ the install-script allowlist is seeded in
  `~/.npmrc` before the installs:
  `allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs,@earendil-works/pi-tui`.
  If an install fails with a blocked-script error, add the package npm names to
  that list and re-run `provision.sh`.
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
later one or the reboot.

DSH and its bundles are installed at **first boot only**, so the monthly pass does
not touch them: `dsh` and `@tomowang/dsh-tui` stay at whatever version
`destroy_first` pinned. Update on demand as `ubuntu` (`npm install -g
@deepseek-ai/dsh`, then `dsh plugin --profile tui add @tomowang/dsh-tui`).

## Destroy

```bash
cd infra/oci && terraform destroy      # or run the workflow with destroy_first
```
