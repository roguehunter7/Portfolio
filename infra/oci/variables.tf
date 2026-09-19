# --- Identity / auth (injected by CI from GitHub secrets) ------------------

# Tenancy OCID doubles as the root-compartment OCID for all resources.
# Set via TF_VAR_tenancy_ocid in CI (same value as the OCI_TENANCY_OCID secret).
variable "tenancy_ocid" {
  description = "Tenancy OCID (also the root compartment OCID)"
  type        = string
}

variable "region" {
  description = "OCI region. Must be the tenancy home region (free-tier resources must live there)."
  type        = string
  default     = "ap-hyderabad-1"
}

# --- VM access --------------------------------------------------------------

variable "ssh_public_key" {
  description = "Public half of the CI deploy key (secret OCI_SSH_PRIVATE_KEY). Injected into the ubuntu user; sshd is loopback-only and reachable solely through the Cloudflare Access tunnel, so the key never crosses a public port."
  type        = string
}

# --- Cloudflare tunnel ------------------------------------------------------

variable "cloudflare_tunnel_token" {
  description = "Tunnel token of the EXISTING Cloudflare tunnel (secret CLOUDFLARE_TUNNEL_TOKEN). Base64 JSON {a,s,t}. Injected into the VM via cloud-init; also lands in OCI tfstate/instance metadata (tunnel-run scope only). Its routes (ssh.sreeramkr.com -> ssh://localhost:22, hermes.sreeramkr.com -> http://localhost:9119) are dashboard-managed and Access-gated."
  type        = string
  sensitive   = true
}

variable "budget_alert_email" {
  description = "Email receiving budget alert notifications when ANY spend is detected."
  type        = string
  default     = "krsreeram007@gmail.com"
}

# --- Hermes Agent (native install on this box) ------------------------------
# These land in the 0600 /etc/hermes/hermes.env via cloud-init and are installed
# into ~/.hermes/.env by provision.sh. Because user_data is stored in the
# instance metadata, the same values are also readable from the instance's own
# IMDS and appear in the tfstate bucket — both private to this tenancy.
# Trade-off documented in infra/oci/README.md.

variable "deepseek_api_key" {
  description = "DeepSeek API key for the Hermes gateway. Passed from GitHub secret DEEPSEEK_API_KEY."
  type        = string
  sensitive   = true
}

variable "telegram_bot_token" {
  description = "Telegram bot token for the Hermes gateway. Passed from GitHub secret TELEGRAM_BOT_TOKEN."
  type        = string
  sensitive   = true
}

variable "telegram_allowed_users" {
  description = "Optional Telegram user-id allowlist (TELEGRAM_ALLOWED_USERS). Empty falls back to Hermes' DM pairing flow."
  type        = string
  sensitive   = true
  default     = ""
}

variable "hermes_dashboard_password" {
  description = "Password for the dashboard's username/password auth provider (user: admin). Passed from GitHub secret HERMES_DASHBOARD_PASSWORD. The dashboard refuses a non-loopback bind without a provider, so this is required."
  type        = string
  sensitive   = true
}

variable "hermes_dashboard_secret" {
  description = "Token-signing key for dashboard sessions (32+ random bytes, e.g. openssl rand -base64 32). Passed from GitHub secret HERMES_DASHBOARD_SECRET. Keep it stable or every restart logs everyone out."
  type        = string
  sensitive   = true
}
