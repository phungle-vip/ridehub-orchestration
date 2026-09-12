provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# ------------------------------------------------------------------------------
# 1. Keycloak OIDC Identity Provider in Cloudflare Zero Trust
# ------------------------------------------------------------------------------
resource "cloudflare_zero_trust_access_identity_provider" "keycloak" {
  account_id = var.cloudflare_account_id
  name       = "Keycloak"
  type       = "oidc"

  config {
    client_id     = var.oidc_client_id
    client_secret = var.oidc_client_secret
    issuer_url    = "https://keycloak.${var.domain}/realms/jhipster"
    auth_url      = "https://keycloak.${var.domain}/realms/jhipster/protocol/openid-connect/auth"
    token_url     = "https://keycloak.${var.domain}/realms/jhipster/protocol/openid-connect/token"
    certs_url     = "https://keycloak.${var.domain}/realms/jhipster/protocol/openid-connect/certs"
    scopes        = ["openid", "email", "profile", "roles"]
  }
}

# ------------------------------------------------------------------------------
# 2. Zero Trust Access Applications & Policies (Protect Kafka UI)
# Note: Grafana, Consul, Vault, RedisInsight use their own native auth mechanisms.
# ------------------------------------------------------------------------------
locals {
  protected_apps = {
    "Kafka UI" = "kafdrop"
  }
}

resource "cloudflare_zero_trust_access_application" "apps" {
  for_each = local.protected_apps

  zone_id                   = var.cloudflare_zone_id
  name                      = each.key
  domain                    = "${each.value}.${var.domain}"
  type                      = "self_hosted"
  session_duration          = "24h"
  auto_redirect_to_identity = true
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.keycloak.id]
}

resource "cloudflare_zero_trust_access_policy" "admin_access" {
  for_each = cloudflare_zero_trust_access_application.apps

  application_id = each.value.id
  zone_id        = var.cloudflare_zone_id
  name           = "Allow Keycloak Authenticated Users"
  decision       = "allow"
  precedence     = 1

  include {
    login_method = [cloudflare_zero_trust_access_identity_provider.keycloak.id]
  }
}

# ------------------------------------------------------------------------------
# 3. SSH Zero Trust Access Application & Policy
# Protects SSH port 22 access via Cloudflare Tunnel (ssh.phungvip.io.vn)
# ------------------------------------------------------------------------------
resource "cloudflare_zero_trust_access_application" "ssh" {
  zone_id                   = var.cloudflare_zone_id
  name                      = "RideHub SSH Server"
  domain                    = "ssh.${var.domain}"
  type                      = "self_hosted"
  session_duration          = "12h"
  auto_redirect_to_identity = true
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.keycloak.id]
}

resource "cloudflare_zero_trust_access_policy" "ssh_policy" {
  application_id = cloudflare_zero_trust_access_application.ssh.id
  zone_id        = var.cloudflare_zone_id
  name           = "Allow Keycloak SSH Admin"
  decision       = "allow"
  precedence     = 1

  include {
    login_method = [cloudflare_zero_trust_access_identity_provider.keycloak.id]
  }
}

# ------------------------------------------------------------------------------
# 4. VPN Management Portal Zero Trust Access (wg-easy)
# Protected by Keycloak OIDC Claim: ONLY ROLE_ADMIN & ROLE_DEVOPS allowed
# ------------------------------------------------------------------------------
resource "cloudflare_zero_trust_access_application" "vpn_portal" {
  zone_id                   = var.cloudflare_zone_id
  name                      = "RideHub VPN Management Portal"
  domain                    = "vpn.${var.domain}"
  type                      = "self_hosted"
  session_duration          = "8h"
  auto_redirect_to_identity = true
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.keycloak.id]
}

resource "cloudflare_zero_trust_access_policy" "vpn_admin_only" {
  application_id = cloudflare_zero_trust_access_application.vpn_portal.id
  zone_id        = var.cloudflare_zone_id
  name           = "Allow Keycloak Authenticated Users"
  decision       = "allow"
  precedence     = 1

  include {
    login_method = [cloudflare_zero_trust_access_identity_provider.keycloak.id]
    email        = [var.admin_email, "admin@localhost", "phungvip@ridehub.vn", "devops@ridehub.vn"]
  }
}

# ------------------------------------------------------------------------------
# 5. DNS CNAME Records (Managed by Terraform)
# ------------------------------------------------------------------------------
resource "cloudflare_record" "ssh" {
  zone_id = var.cloudflare_zone_id
  name    = "ssh"
  type    = "CNAME"
  content = "${var.infra_tunnel_id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_record" "vpn" {
  zone_id = var.cloudflare_zone_id
  name    = "vpn"
  type    = "CNAME"
  content = "${var.infra_tunnel_id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# ------------------------------------------------------------------------------
# 5. WARP Private Network Routes (Access LAN / Docker Subnets via WARP Client)
# Note: Yêu cầu Cloudflare API Token có quyền: Account -> Cloudflare Tunnel -> Edit
# Sau khi cấp quyền trên Cloudflare Dashboard (My Profile -> API Tokens), mở comment bên dưới:
# ------------------------------------------------------------------------------
resource "cloudflare_zero_trust_tunnel_route" "infra_network" {
  account_id = var.cloudflare_account_id
  tunnel_id  = var.infra_tunnel_id
  network    = "172.18.0.0/16"
  comment    = "RideHub Infra Docker Network (Redis, Kafka, Consul, Vault)"
}

resource "cloudflare_zero_trust_tunnel_route" "ms_network" {
  account_id = var.cloudflare_account_id
  tunnel_id  = var.infra_tunnel_id
  network    = "172.19.0.0/16"
  comment    = "RideHub Microservices Docker Network (MySQLs)"
}
