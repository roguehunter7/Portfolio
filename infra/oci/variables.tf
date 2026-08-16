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
  description = "Public SSH key injected into the VM (ubuntu user). Passed from GitHub var OCI_SSH_PUBLIC_KEY."
  type        = string
}

variable "ssh_hostname" {
  description = "Public hostname on the Cloudflare tunnel mapped to SSH (localhost:22)."
  type        = string
  default     = "ssh.sreeramkr.com"
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

variable "ttyd_password" {
  description = "Password for the ttyd browser terminal login (user: reasonix). Passed from GitHub secret TTYD_PASSWORD."
  type        = string
  sensitive   = true
}
