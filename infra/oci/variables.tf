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
  description = "Public SSH key injected into the VM (ubuntu user). No SSH server runs; kept only as a fallback if one is reinstalled. Passed from GitHub var OCI_SSH_PUBLIC_KEY."
  type        = string
}

# --- Cloudflare tunnel ------------------------------------------------------

variable "cloudflare_tunnel_token" {
  description = "Tunnel token of the EXISTING Cloudflare tunnel (secret CLOUDFLARE_TUNNEL_TOKEN). Base64 JSON {a,s,t}. Injected into the VM via cloud-init; also lands in OCI tfstate/instance metadata (tunnel-run scope only)."
  type        = string
  sensitive   = true
}

variable "budget_alert_email" {
  description = "Email receiving budget alert notifications when ANY spend is detected."
  type        = string
  default     = "krsreeram007@gmail.com"
}

# --- Hermes Agent + DeepSeek Harness (run natively on this box) -------------
# These land in 0600 files (/etc/hermes/hermes.env, /etc/dsh/env) via
# cloud-init. Because user_data is stored in the instance metadata, the same
# values are also readable from the instance's own IMDS and appear in the
# tfstate bucket — both private to this tenancy. Trade-off documented in
# infra/oci/README.md.

variable "deepseek_api_key" {
  description = "DeepSeek API key for the Hermes gateway and the staged DSH env. Passed from GitHub secret DEEPSEEK_API_KEY."
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
