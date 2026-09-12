#!/usr/bin/env bash
# ==============================================================================
# RIDEHUB HOST FIREWALL SETUP - VPS 2 (MICROSERVICES)
# Thiết lập tường lửa UFW cho máy chủ Microservices & Databases
# Tham chiếu: docs/guides/WIREGUARD_UFW_GUIDE.md (Chương 5)
# ==============================================================================
set -euo pipefail

ADMIN_IP="10.10.0.3"
WG_SUBNET="10.10.0.0/24"

echo "=========================================================="
echo "🛡️  Đang thiết lập Tường lửa UFW cho VPS 2 (Microservices)..."
echo "=========================================================="

# 1. Reset UFW và thiết lập default policies
echo "[1/6] Đặt chính sách mặc định: Deny Incoming, Allow Outgoing..."
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# 2. Mở cổng Ingress công khai
echo "[2/6] Mở các cổng Ingress công khai (HTTP 80, HTTPS 443)..."
sudo ufw allow 80/tcp comment "HTTP Ingress (Cloudflare / ACME)"
sudo ufw allow 443/tcp comment "HTTPS Ingress (Cloudflare / SSL)"

# 3. Mở lưu lượng trên card mạng ảo WireGuard (wg0)
echo "[3/6] Cho phép toàn bộ subnet mạng nội bộ ${WG_SUBNET} qua wg0..."
sudo ufw allow in on wg0 comment "Allow WireGuard Subnet 10.10.0.0/24"

# 4. Stealth SSH: Chỉ mở riêng cho IP Admin WireGuard
echo "[4/6] Cấu hình Stealth SSH (Chỉ cho phép Admin ${ADMIN_IP})..."
sudo ufw allow from "${ADMIN_IP}" to any port 22 proto tcp comment "Admin Stealth SSH"
sudo ufw deny from "${WG_SUBNET}" to any port 22 proto tcp comment "Block Non-Admin SSH"

# 5. Mở các port MySQLs (3306 - 3310) cho Admin quản trị
echo "[5/6] Mở các port MySQL (3306 - 3310) cho Admin (${ADMIN_IP})..."
sudo ufw allow from "${ADMIN_IP}" to any port 3306:3310 proto tcp comment "Admin All MySQLs"

# 6. Kích hoạt UFW
echo "[6/6] Kích hoạt UFW..."
sudo ufw --force enable
sudo ufw status numbered

echo "=========================================================="
echo "✅ Hoàn tất thiết lập tường lửa UFW cho VPS 2!"
echo "=========================================================="

