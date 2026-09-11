# ==============================================================================
# Terraform Microservices Image Builder & Deployment Integrator
# ==============================================================================
# Tích hợp trực tiếp với kịch bản auto-deploy.sh của infra/vps-microservices.
# ==============================================================================

variable "enable_microservices_build" {
  description = "Bật tính năng build Docker images cho các microservices"
  type        = bool
  default     = false
}

variable "target_service" {
  description = "Service cần build (mặc định 'all' để build toàn bộ)"
  type        = string
  default     = "all"
}

resource "terraform_data" "microservice_build" {
  count = var.enable_microservices_build ? 1 : 0

  triggers_replace = [
    timestamp()
  ]

  provisioner "local-exec" {
    working_dir = "${path.module}/../../vps-microservices"
    command     = var.target_service == "all" ? "bash config/scripts/auto-deploy.sh --skip-pull -a" : "bash config/scripts/auto-deploy.sh --skip-pull -s ${var.target_service}"
  }
}

output "microservices_build_status" {
  description = "Trạng thái trigger build microservices"
  value       = var.enable_microservices_build ? "Triggered auto-deploy.sh for ${var.target_service}" : "Build disabled"
}
