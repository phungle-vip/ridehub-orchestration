# ==============================================================================
# RIDEHUB CLOUDFLARE DNS MANAGEMENT (IaC)
# Thay thế hoàn toàn các lệnh curl / cloudflared route dns thủ công trong shell script
# ==============================================================================

locals {
  # Subdomains trỏ về cụm VPS-Microservices (Tunnel 2)
  microservice_subdomains = [
    "@",
    "gateway",
    "apigateway",
    "webhook",
    "msuser",
    "msroute",
    "msbooking",
    "mspromotion"
  ]

  # Subdomains trỏ về cụm VPS-Infra (Tunnel 1)
  infra_subdomains = [
    "consul",
    "vault",
    "kafka",
    "kafdrop",
    "redis",
    "redisinsight",
    "prometheus",
    "loki",
    "grafana",
    "keycloak",
    "repo"
  ]
}

# 1. DNS Records cho Microservices Cluster
resource "cloudflare_record" "microservices" {
  for_each = toset(local.microservice_subdomains)
  zone_id  = var.cloudflare_zone_id
  name     = each.key
  type     = "CNAME"
  content  = "${var.ms_tunnel_id}.cfargotunnel.com"
  proxied  = true
  ttl      = 1
}

# 2. DNS Records cho Infrastructure Cluster
resource "cloudflare_record" "infra" {
  for_each = toset(local.infra_subdomains)
  zone_id  = var.cloudflare_zone_id
  name     = each.key
  type     = "CNAME"
  content  = "${var.infra_tunnel_id}.cfargotunnel.com"
  proxied  = true
  ttl      = 1
}
