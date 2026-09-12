#!/usr/bin/env bash
# ==============================================================================
# RIDEHUB HOST FIREWALL SETUP - VPS 1 (INFRA HUB)
# Thiết lập tường lửa UFW cho máy chủ Hạ Tầng Trung Tâm
# Tham chiếu: docs/guides/WIREGUARD_UFW_GUIDE.md (Chương 5)
# ==============================================================================
set -euo pipefail

ADMIN_IP="10.10.0.3"
VPS2_IP="10.10.0.2"
WG_SUBNET="10.10.0.0/24"

echo "=========================================================="
echo "🛡️  Đang thiết lập Tường lửa UFW cho VPS 1 (Infra Hub)..."
echo "=========================================================="

# 1. Reset UFW và thiết lập default policies
echo "[1/6] Đặt chính sách mặc định: Deny Incoming, Allow Outgoing..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# 2. Mở cổng Ingress công khai
echo "[2/6] Mở các cổng Ingress công khai (WireGuard UDP 51820, HTTP 80, HTTPS 443)..."
sudo ufw allow 51820/udp comment "WireGuard VPN Endpoint"
sudo ufw allow 80/tcp comment "HTTP Ingress (Cloudflare / ACME)"
sudo ufw allow 443/tcp comment "HTTPS Ingress (Cloudflare / SSL)"

# 3. Mở lưu lượng trên card mạng ảo WireGuard (wg0)
echo "[3/6] Cho phép toàn bộ subnet mạng nội bộ ${WG_SUBNET} qua wg0..."
sudo ufw allow in on wg0 comment "Allow WireGuard Subnet 10.10.0.0/24"

# 4. Stealth SSH: Chỉ mở riêng cho IP Admin WireGuard
echo "[4/6] Cấu hình Stealth SSH (Chỉ cho phép Admin ${ADMIN_IP})..."
sudo ufw allow from "${ADMIN_IP}" to any port 22 proto tcp comment "Admin Stealth SSH"
sudo ufw deny from "${WG_SUBNET}" to any port 22 proto tcp comment "Block Non-Admin SSH"

# 5. Mở các port dịch vụ nội bộ cho VPS 2 (Microservices)
echo "[5/6] Mở các port Kafka, Redis, Consul, Vault cho VPS 2 (${VPS2_IP})..."
sudo ufw allow from "${VPS2_IP}" to any port 9093 proto tcp comment "VPS2 Kafka SASL_SSL"
sudo ufw allow from "${VPS2_IP}" to any port 6379 proto tcp comment "VPS2 Redis Cache"
sudo ufw allow from "${VPS2_IP}" to any port 8500 proto tcp comment "VPS2 Consul API/UI"
sudo ufw allow from "${VPS2_IP}" to any port 8200 proto tcp comment "VPS2 Vault API"

# 6. Kích hoạt UFW
echo "[6/6] Kích hoạt UFW..."
sudo ufw --force enable
sudo ufw status numbered

echo "=========================================================="
echo "✅ Hoàn tất thiết lập tường lửa UFW cho VPS 1!"
echo "=========================================================="

