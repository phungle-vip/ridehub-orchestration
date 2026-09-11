# ==============================================================================
# RIDEHUB INFRASTRUCTURE AS CODE (IaC): VAULT & CONSUL
# Quản lý tập trung Secrets, Policies & ACL Tokens qua Terraform
# Loại bỏ hoàn toàn việc tạo và lưu file .env thủ công
# ==============================================================================

provider "vault" {
  address = var.vault_address
  token   = var.vault_token != "" ? var.vault_token : null
}

provider "consul" {
  address    = var.consul_address
  scheme     = "https"
  token      = var.consul_token != "" ? var.consul_token : null
  datacenter = "dc1"
}

# ------------------------------------------------------------------------------
# 1. Vault Policies & Secret Management
# ------------------------------------------------------------------------------

# Policy cấp quyền Read-Only cho Microservices và Developers kết nối Vault
resource "vault_policy" "microservices_readonly" {
  name = "microservices-readonly"

  policy = <<-EOT
    # Microservices & Devs read shared infrastructure secrets
    path "secret/data/infrastructure" {
      capabilities = ["read", "list"]
    }
    path "secret/metadata/infrastructure" {
      capabilities = ["read", "list"]
    }

    # Microservices read their own service-specific configs
    path "secret/data/application" {
      capabilities = ["read", "list"]
    }
    path "secret/metadata/application" {
      capabilities = ["read", "list"]
    }
    path "secret/data/*" {
      capabilities = ["read", "list"]
    }
    path "secret/metadata/*" {
      capabilities = ["read", "list"]
    }
  EOT
}

# ------------------------------------------------------------------------------
# 2. Consul ACL Policies & Service Tokens
# ------------------------------------------------------------------------------

# Developer Read-Only Policy (không cho phép ghi, xóa, hay sửa ACL)
resource "consul_acl_policy" "developer_readonly" {
  name        = "developer-readonly-policy"
  description = "Read-only access for developers to inspect catalog and health checks"
  rules       = <<-RULE
    service_prefix "" {
      policy = "read"
    }
    node_prefix "" {
      policy = "read"
    }
    key_prefix "" {
      policy = "read"
    }
  RULE
}

# Danh sách microservices cốt lõi của RideHub
locals {
  services = {
    "apigateway"  = "API Gateway service discovery and KV read"
    "msuser"      = "User Microservice discovery and KV read"
    "msroute"     = "Route Microservice discovery and KV read"
    "msbooking"   = "Booking Microservice discovery and KV read"
    "mspromotion" = "Promotion Microservice discovery and KV read"
  }
}

# Policy cho từng microservice đăng ký Consul Discovery và đọc KV config
resource "consul_acl_policy" "service" {
  for_each    = local.services
  name        = "svc-${each.key}-policy"
  description = each.value
  rules       = <<-RULE
    service "${each.key}" {
      policy = "write"
    }
    key_prefix "config/${each.key}/" {
      policy = "read"
    }
    key_prefix "config/application/" {
      policy = "read"
    }
    agent_prefix "" {
      policy = "read"
    }
    node_prefix "" {
      policy = "read"
    }
  RULE
}

# ACL Token cho từng microservice được Terraform tự sinh và quản lý
resource "consul_acl_token" "service_token" {
  for_each    = local.services
  description = "Token for ${each.key} service"
  policies    = [consul_acl_policy.service[each.key].name]
  local       = true
}

# ------------------------------------------------------------------------------
# Outputs: Xuất các token để microservices dùng nếu cần
# ------------------------------------------------------------------------------
output "consul_service_tokens" {
  description = "Map of microservice names to their Consul ACL tokens"
  value = {
    for k, v in consul_acl_token.service_token : k => v.accessor_id
  }
  sensitive = false
}
