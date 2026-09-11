variable "cloudflare_api_token" {
  description = "Cloudflare API Token with Zone.DNS and Account.Access permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for the target domain"
  type        = string
}

variable "domain" {
  description = "Base domain name for RideHub"
  type        = string
  default     = "phungvip.io.vn"
}

variable "admin_email" {
  description = "Admin email address for Cloudflare Access policies"
  type        = string
  default     = "admin@phungvip.io.vn"
}

variable "oidc_client_id" {
  description = "Keycloak OIDC Client ID for Cloudflare Access"
  type        = string
  default     = "web_app"
}

variable "oidc_client_secret" {
  description = "Keycloak OIDC Client Secret for Cloudflare Access"
  type        = string
  sensitive   = true
}

variable "infra_tunnel_id" {
  description = "Cloudflare Tunnel ID for the VPS Infra cluster"
  type        = string
  default     = "6c1ea060-1d61-4254-94ee-f79d85b1ba8e"
}

# ------------------------------------------------------------------------------
# Vault & Consul Centralized Secrets Management
# ------------------------------------------------------------------------------
variable "vault_address" {
  description = "HashiCorp Vault URL"
  type        = string
  default     = "https://vault.phungvip.io.vn"
}

variable "vault_token" {
  description = "HashiCorp Vault management root token (can also be read from VAULT_TOKEN env var)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "consul_address" {
  description = "Consul cluster address"
  type        = string
  default     = "consul.phungvip.io.vn:443"
}

variable "consul_token" {
  description = "Consul management token (can also be read from CONSUL_HTTP_TOKEN env var)"
  type        = string
  sensitive   = true
  default     = ""
}

