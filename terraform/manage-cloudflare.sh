#!/usr/bin/env bash
# ==============================================================================
# RideHub Cloudflare Zero Trust & DNS Automation Script
# ==============================================================================
# Tự động hóa: Kiểm tra trạng thái, Xóa sạch (Destroy) và Khôi phục (Reset)
# cấu hình Cloudflare về trạng thái mặc định chuẩn (Keycloak IdP, Access Apps, SSH, DNS).
#
# Cách sử dụng:
#   ./manage-cloudflare.sh --status   # Kiểm tra trạng thái DNS, Access Apps & Policies hiện tại
#   ./manage-cloudflare.sh --apply    # Cài đặt / Đồng bộ cấu hình mặc định chuẩn
#   ./manage-cloudflare.sh --destroy  # Xóa sạch toàn bộ Access Apps, Policies & DNS đã tạo
#   ./manage-cloudflare.sh --reset    # Xóa sạch rồi cài đặt lại từ đầu (Clean Fresh Install)
# ==============================================================================
set -euo pipefail

# Màu sắc hiển thị
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Xác định đường dẫn thư mục gốc và thư mục terraform
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/main.tf" ]; then
  TF_DIR="${SCRIPT_DIR}"
elif [ -d "${SCRIPT_DIR}/../orchestration/terraform" ]; then
  TF_DIR="$(cd "${SCRIPT_DIR}/../orchestration/terraform" && pwd)"
elif [ -d "${SCRIPT_DIR}/../../orchestration/terraform" ]; then
  TF_DIR="$(cd "${SCRIPT_DIR}/../../orchestration/terraform" && pwd)"
elif [ -d "/home/phungvip/ridehub/infra/orchestration/terraform" ]; then
  TF_DIR="/home/phungvip/ridehub/infra/orchestration/terraform"
else
  echo -e "${RED}❌ Không tìm thấy thư mục infra/orchestration/terraform!${NC}"
  exit 1
fi

TFVARS_FILE="${TF_DIR}/terraform.tfvars"

# Đọc cấu hình từ terraform.tfvars
read_tfvars() {
  if [ ! -f "$TFVARS_FILE" ]; then
    echo -e "${RED}❌ Không tìm thấy $TFVARS_FILE!${NC}"
    exit 1
  fi
  CF_API_TOKEN=$(grep -E '^\s*cloudflare_api_token\s*=' "$TFVARS_FILE" | sed -E 's/.*"([^"]+)".*/\1/')
  CF_ACCOUNT_ID=$(grep -E '^\s*cloudflare_account_id\s*=' "$TFVARS_FILE" | sed -E 's/.*"([^"]+)".*/\1/')
  CF_ZONE_ID=$(grep -E '^\s*cloudflare_zone_id\s*=' "$TFVARS_FILE" | sed -E 's/.*"([^"]+)".*/\1/')
  DOMAIN=$(grep -E '^\s*domain\s*=' "$TFVARS_FILE" | sed -E 's/.*"([^"]+)".*/\1/' || echo "phungvip.io.vn")
}

check_terraform() {
  if ! command -v terraform >/dev/null 2>&1; then
    echo -e "${RED}❌ Không tìm thấy công cụ 'terraform' trên máy! Vui lòng cài đặt terraform.${NC}"
    exit 1
  fi
  if [ ! -d "${TF_DIR}/.terraform" ]; then
    echo -e "${CYAN}⚙️ Đang khởi tạo Terraform provider...${NC}"
    (cd "$TF_DIR" && terraform init)
  fi
}

show_status() {
  read_tfvars
  echo -e "${BLUE}======================================================================${NC}"
  echo -e "${BLUE}🔍 KIỂM TRA TRẠNG THÁI CLOUDFLARE ZERO TRUST & DNS (Domain: ${DOMAIN})${NC}"
  echo -e "${BLUE}======================================================================${NC}"

  # 1. Kiểm tra Keycloak IdP
  echo -e "\n${CYAN}1. Identity Providers (IdP):${NC}"
  IDP_RES=$(curl -s -H "Authorization: Bearer ${CF_API_TOKEN}" "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/access/identity_providers")
  IDP_COUNT=$(echo "$IDP_RES" | python3 -c 'import sys, json; data=json.load(sys.stdin); print(len(data.get("result", [])))' 2>/dev/null || echo "0")
  if [ "$IDP_COUNT" -gt 0 ]; then
    echo "$IDP_RES" | python3 -c '
import sys, json
data = json.load(sys.stdin)
for r in data.get("result", []):
    name = r.get("name", "")
    t = r.get("type", "")
    rid = r.get("id", "")
    print(f"   ✓ IdP: {name} (Type: {t}, ID: {rid})")
'
  else
    echo -e "   ${YELLOW}⚠ Chưa có Identity Provider nào được cấu hình.${NC}"
  fi

  # 2. Kiểm tra Access Applications
  echo -e "\n${CYAN}2. Zero Trust Access Applications:${NC}"
  APPS_RES=$(curl -s -H "Authorization: Bearer ${CF_API_TOKEN}" "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/access/apps")
  APP_COUNT=$(echo "$APPS_RES" | python3 -c 'import sys, json; data=json.load(sys.stdin); print(len(data.get("result", [])))' 2>/dev/null || echo "0")
  if [ "$APP_COUNT" -gt 0 ]; then
    echo "$APPS_RES" | python3 -c '
import sys, json
data = json.load(sys.stdin)
for r in data.get("result", []):
    name = r.get("name", "")
    dom = r.get("domain", "")
    policies = len(r.get("policies", []))
    print(f"   ✓ App: {name:25} | Domain: {dom:30} | Policies: {policies}")
'
  else
    echo -e "   ${YELLOW}⚠ Chưa có Access Application nào.${NC}"
  fi

  # 3. Kiểm tra bản ghi DNS ssh
  echo -e "\n${CYAN}3. Bản ghi DNS 'ssh.${DOMAIN}':${NC}"
  DNS_RES=$(curl -s -H "Authorization: Bearer ${CF_API_TOKEN}" "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?name=ssh.${DOMAIN}")
  DNS_COUNT=$(echo "$DNS_RES" | python3 -c 'import sys, json; data=json.load(sys.stdin); print(len(data.get("result", [])))' 2>/dev/null || echo "0")
  if [ "$DNS_COUNT" -gt 0 ]; then
    echo "$DNS_RES" | python3 -c '
import sys, json
data = json.load(sys.stdin)
for r in data.get("result", []):
    name = r.get("name", "")
    content = r.get("content", "")
    proxied = r.get("proxied", False)
    print(f"   ✓ DNS: {name} -> {content} (Proxied: {proxied})")
'
  else
    echo -e "   ${YELLOW}⚠ Chưa có bản ghi DNS cho ssh.${DOMAIN}.${NC}"
  fi

  # 4. Kiểm tra WARP Private Network Routes
  echo -e "\n${CYAN}4. WARP Private Network Routes (Mạng LAN nội bộ):${NC}"
  ROUTES_RES=$(curl -s -H "Authorization: Bearer ${CF_API_TOKEN}" "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/teamnet/routes")
  ROUTES_COUNT=$(echo "$ROUTES_RES" | python3 -c 'import sys, json; data=json.load(sys.stdin); print(len(data.get("result", [])))' 2>/dev/null || echo "0")
  if [ "$ROUTES_COUNT" -gt 0 ]; then
    echo "$ROUTES_RES" | python3 -c '
import sys, json
data = json.load(sys.stdin)
for r in data.get("result", []):
    net = r.get("network", "")
    comm = r.get("comment", "")
    tun = r.get("tunnel_name", "")
    print(f"   ✓ Subnet: {net:18} | Tunnel: {tun:22} | Mô tả: {comm}")
'
  else
    echo -e "   ${YELLOW}⚠ Chưa có Private Network Route nào.${NC}"
  fi

  echo -e "\n${GREEN}✓ Hoàn tất kiểm tra trạng thái!${NC}"
}

apply_default() {
  check_terraform
  read_tfvars
  echo -e "${CYAN}======================================================================${NC}"
  echo -e "${CYAN}🚀 ĐANG CÀI ĐẶT / ĐỒNG BỘ CẤU HÌNH CLOUDFLARE VỀ MẶC ĐỊNH CHUẨN...${NC}"
  echo -e "${CYAN}======================================================================${NC}"
  echo -e "Thư mục Terraform: $TF_DIR"

  (cd "$TF_DIR" && terraform apply -auto-approve)

  echo -e "\n${GREEN}🎉 CÀI ĐẶT THÀNH CÔNG!${NC}"
  echo -e "Kiểm tra kết nối các dịch vụ:"
  echo -e " - Kafka UI  : https://kafdrop.${DOMAIN} (Bảo vệ bởi Keycloak OIDC)"
  echo -e " - SSH Server: ssh.${DOMAIN} (Bảo vệ bởi Keycloak OIDC)"
}

destroy_all() {
  check_terraform
  read_tfvars
  echo -e "${RED}======================================================================${NC}"
  echo -e "${RED}⚠️  CẢNH BÁO: ĐANG TIẾN HÀNH XÓA TOÀN BỘ CẤU HÌNH CLOUDFLARE...${NC}"
  echo -e "${RED}======================================================================${NC}"
  echo -e "Thao tác này sẽ gỡ bỏ:"
  echo -e " - Access Applications (Kafka UI, SSH Server)"
  echo -e " - Access Policies"
  echo -e " - Bản ghi DNS ssh.${DOMAIN}"
  echo -e " - Keycloak OIDC Identity Provider\n"

  (cd "$TF_DIR" && terraform destroy -auto-approve)

  echo -e "\n${GREEN}✓ Đã dọn dẹp sạch sẽ toàn bộ cấu hình trên Cloudflare!${NC}"
}

reset_clean() {
  echo -e "${YELLOW}======================================================================${NC}"
  echo -e "${YELLOW}🔄 BẮT ĐẦU QUY TRÌNH RESET TOÀN DIỆN (DESTROY -> FRESH APPLY)${NC}"
  echo -e "${YELLOW}======================================================================${NC}"
  destroy_all
  echo -e "\n${CYAN}Đang chuẩn bị cài đặt lại từ đầu...${NC}\n"
  sleep 2
  apply_default
}

build_images() {
  check_terraform
  local target_service="${2:-all}"
  echo -e "${CYAN}======================================================================${NC}"
  echo -e "${CYAN}🔨 ĐANG BUILD & DEPLOY MICROSERVICES QUA PIPELINE TỰ ĐỘNG (AUTO-DEPLOY)${NC}"
  echo -e "${CYAN}======================================================================${NC}"
  echo -e "-> Mục tiêu triển khai: ${target_service}"
  (cd "$TF_DIR" && terraform apply -var="enable_microservices_build=true" -var="target_service=${target_service}" -auto-approve)
  echo -e "\n${GREEN}✓ Build & Deploy Microservices hoàn tất!${NC}"
}

# Xử lý tham số dòng lệnh
MODE="${1:---help}"

case "$MODE" in
  --status|-s)
    show_status
    ;;
  --apply|-a|--install)
    apply_default
    ;;
  --destroy|-d|--clean)
    destroy_all
    ;;
  --reset|-r)
    reset_clean
    ;;
  --build-images|-b)
    build_images "$@"
    ;;
  --help|-h|*)
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "${CYAN}🛠️  RIDEHUB CLOUDFLARE ZERO TRUST & DNS MANAGEMENT CLI${NC}"
    echo -e "${CYAN}======================================================================${NC}"
    echo -e "Cú pháp:"
    echo -e "  $0 --status         # Xem trạng thái DNS, Access Apps & Policies, WARP Routes"
    echo -e "  $0 --apply          # Cài đặt / Đồng bộ về mặc định chuẩn (IdP, Apps, SSH, DNS, WARP)"
    echo -e "  $0 --destroy        # Xóa sạch toàn bộ cấu hình đã tạo trên Cloudflare"
    echo -e "  $0 --reset          # Xóa sạch rồi cài đặt lại từ đầu (Clean Reinstall)"
    echo -e "  $0 --build-images   # Build Docker images cho microservices qua Terraform (Maven Jib)"
    echo -e "  $0 --build-images <service> # Build riêng 1 service (vd: gateway, ms_user)"
    echo -e ""
    show_status
    ;;
esac
