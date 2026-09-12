# 🌐 RideHub Infrastructure Orchestration (IaC & Multi-VPS Automation)

> **Mục tiêu**: Thư mục điều phối tập trung toàn bộ hạ tầng đám mây (Cloudflare), tự động hóa triển khai máy chủ (Ansible), mạng LAN ảo hiệu năng cao (**WireGuard Layer 4**), tường lửa phân quyền (**UFW**), và môi trường giả lập Multi-VPS (Mock).
> **Tuân thủ**: Nguyên tắc kiến trúc `AGENTS.md` (Độc lập Submodule, Database per Service, Zero Localhost Assumption, Bảo mật Zero Trust).

---

## 🏛️ 1. Mô Hình Kiến Trúc Mạng Chuẩn Hóa (Dual-Layer Network)

Hệ thống hạ tầng phân tán 2 VPS của RideHub được phân tầng ranh giới tuyệt đối:

```text
[ Người Dùng & Khách Hàng ]                [ Admin / DevOps ]                 [ Lập Trình Viên (Dev) ]
             │                                      │                                      │
             ▼ (HTTPS Công Khai)                    ▼ (Browser Web Terminal)               ▼ (App WireGuard)
┌───────────────────────────────┐     ┌───────────────────────────────┐      ┌───────────────────────────────┐
│     CLOUDFLARE INGRESS        │     │    CLOUDFLARE ZERO TRUST      │      │     WIREGUARD VPN TUNNEL      │
│  - phungvip.io.vn             │     │  - ssh.phungvip.io.vn         │      │  - vpn.phungvip.io.vn         │
│  - gateway.phungvip.io.vn     │     │  - Check Keycloak OIDC Role:  │      │  - Cấp IP: 10.10.0.4+         │
│  - repo.phungvip.io.vn        │     │    ROLE_ADMIN / ROLE_DEVOPS   │      │  - UFW trói IP: Cấm SSH 22,   │
│  - keycloak.phungvip.io.vn    │     │  - Render Web Terminal đen    │      │    chỉ mở Kafka/Redis/MySQL   │
└───────────────┬───────────────┘     └───────────────┬───────────────┘      └───────────────┬───────────────┘
                │                                     │                                      │
                ▼ (Port 443 HTTPS)                    ▼                                      ▼ (Port 51820 UDP)
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ 🔒 MẠNG LAN NỘI BỘ WIREGUARD KERNEL (10.10.0.0/24) + TƯỜNG LỬA UFW                                          │
├─────────────────────────────────────────────┬───────────────────────────────────────────────────────────────┤
│          VPS 1 (Infra Hub - 10.10.0.1)      │              VPS 2 (Microservices - 10.10.0.2)                │
├─────────────────────────────────────────────┼───────────────────────────────────────────────────────────────┤
│ • Keycloak OIDC (Port 9080)                 │ • Spring Cloud Gateway (Port 8080)                            │
│ • Kafka Broker SASL_SSL (Port 10.10.0.1:9093│ • Microservices: ms_user, ms_booking, ms_route, ms_promotion  │
│ • Redis Cache (Port 10.10.0.1:6379)         │ • 4 x MySQL Databases (Ports 10.10.0.2:3307 - 3310)           │
│ • HashiCorp Consul & Vault                  │ • Nginx Ingress Reverse Proxy                                 │
│ • Reposilite (Private Maven Registry)       │ • Observability Agents (Promtail, Prom-agent, cAdvisor)       │
│ • wg-easy (VPN Portal: vpn.phungvip.io.vn)  │                                                               │
│ • Observability Hub: Prometheus, Loki,      │                                                               │
│   Grafana, Kafdrop                          │                                                               │
└─────────────────────────────────────────────┴───────────────────────────────────────────────────────────────┘
```

---

## 🎯 2. Ma Trận Giải Quyết 3 Bài Toán Cốt Lõi (Use Cases)

| Bài toán | Công nghệ lựa chọn | Trải nghiệm & Cơ chế bảo mật | Đánh giá hiệu năng |
|---|---|---|---|
| **Case 1: Admin SSH vào VPS** | **Cloudflare Zero Trust + Keycloak OIDC** | Mở trình duyệt vào `https://ssh.phungvip.io.vn`, đăng nhập Keycloak (kiểm tra claim `ROLE_ADMIN` / `ROLE_DEVOPS`) ➡️ Render Web Terminal đen trực tiếp trên trình duyệt. **Zero-client (không cần cài app)**. | Tiện dụng tối đa, bảo mật 2 lớp qua Cloudflare Edge. |
| **Case 2: VPS to VPS (Backend M2M)** | **WireGuard Kernel P2P + UFW** | VPS 2 kết nối trực tiếp sang VPS 1 qua IP nội bộ `10.10.0.1`. Kafka (9093) và Redis (6379) chỉ bind lắng nghe trên `10.10.0.1`, đóng kín 100% với Internet. | **Đỉnh cao**: Ping 1-3ms, RAM ~3MB, không token timeout, hoạt động bền bỉ 24/7. |
| **Case 3: Dev vào LAN để code** | **WireGuard Profile (`wg-easy`) + UFW Trói IP** | Dev truy cập `https://vpn.phungvip.io.vn` (xác thực Keycloak) để tải file `.conf` hoặc quét mã QR nạp vào app WireGuard. Tường lửa UFW **khóa chặt port 22**, chỉ cho phép vào đúng Kafka, Redis và MySQL phụ trách. | Test service liên thông siêu mượt, thu hồi quyền (offboarding) trong 0.1s khi dev nghỉ việc. |

---

## 📁 3. Cấu Trúc Thư Mục Điều Phối

```text
infra/orchestration/
│
├── terraform/                     # ☁️ Quản lý Cloudflare qua Infrastructure as Code
│   ├── versions.tf                # Khai báo Provider Cloudflare >= 4.40
│   ├── variables.tf               # Biến đầu vào: tokens, account_id, zone_id, domain
│   ├── main.tf                    # Tạo Tunnels, Zero Trust Apps (Kafdrop, Browser SSH, IdP Keycloak)
│   ├── dns.tf                     # Quản lý 18 DNS CNAMEs cho Infra & Microservices
│   ├── outputs.tf                 # Xuất TUNNEL_TOKEN cho Ansible
│   ├── terraform.tfvars.example   # File mẫu biến môi trường Cloudflare
│   └── manage-cloudflare.sh       # Script quản trị Cloudflare & build Jib images
│
├── ansible/                       # ⚙️ Tự động hóa & Điều phối Multi-VPS
│   ├── ansible.cfg                # Cấu hình Ansible
│   ├── inventory.ini              # Khai báo máy chủ thật hoặc Mock
│   ├── site.yml                   # Master Playbook điều phối toàn bộ 5 giai đoạn
│   ├── group_vars/all.yml         # Biến môi trường mạng & domain
│   ├── roles/                     # Các vai trò điều phối:
│   │   ├── common/                # Chuẩn hóa OS, Docker Engine, Docker Compose
│   │   ├── mesh_network/          # Thiết lập & kiểm tra mạng WireGuard (10.10.0.0/24)
│   │   ├── deploy_infra/          # Điều phối cụm vps-infra (Kafka, Redis, Keycloak, wg-easy)
│   │   └── deploy_microservices/  # Điều phối cụm vps-microservices (Gateway, MySQLs, Apps)
│   │
│   └── mock/                      # 🖥️ Môi trường giả lập 2 VPS trên 1 máy chủ
│       ├── Dockerfile.mock-vps    # Debian Trixie + OpenSSH + Docker CLI
│       └── docker-compose.mock.yml# Tạo 2 Nodes (vps1: 2221, vps2: 2222)
│
└── REAL_VPS_GUIDE.md              # 🌐 Cẩm nang từng bước triển khai trên 2 VPS vật lý thật
```

---

## 🚀 4. Hướng Dẫn Vận Hành Nhanh

### Bước 1: Build Docker Images Cho Microservices (Maven Jib)
```bash
# Build độc lập cả 5 services lên Docker daemon:
infra/orchestration/terraform/manage-cloudflare.sh --build-images

# Hoặc build riêng lẻ 1 service (ví dụ gateway):
infra/orchestration/terraform/manage-cloudflare.sh --build-images gateway
```

### Bước 2: Đồng bộ Hạ Tầng Cloudflare (Terraform)
```bash
cd infra/orchestration/terraform
terraform init
terraform apply -auto-approve
```

### Bước 3: Điều Phối Triển Khai Toàn Diện Bằng Ansible
```bash
cd infra/orchestration/ansible

# Chạy trên môi trường giả lập (Mock):
docker compose -f mock/docker-compose.mock.yml up -d
ansible-playbook site.yml

# Chạy trên VPS Thật:
# (Sau khi điền IP thật vào inventory.ini và group_vars/all.yml)
ansible-playbook site.yml
```

---

* 📖 [**`docs/guides/WIREGUARD_UFW_GUIDE.md`**](../../docs/guides/WIREGUARD_UFW_GUIDE.md): **Cẩm nang Toàn Tập Mạng Dual-Layer, WireGuard, Cổng VPN & Tường Lửa UFW** — Tổng hợp trọn vẹn từ A-Z kiến trúc mạng 2 lớp (L7 vs L4), mạng LAN ảo WireGuard Kernel (`10.10.0.0/24`), cổng cấp key tự phục vụ `https://vpn.phungvip.io.vn`, thiết kế tích hợp Grafana và toàn bộ ma trận tường lửa UFW Rules.
* 📖 [**`infra/orchestration/REAL_VPS_GUIDE.md`**](REAL_VPS_GUIDE.md): **Hướng dẫn đưa lên 2 VPS vật lý thật** — Chuẩn bị phần cứng, cấu hình SSH key, rsync code, kiểm tra mạng TCP Layer 4.
* 📖 [**`AGENTS.md`**](../../AGENTS.md): **Quy chuẩn kiến trúc hệ thống RideHub** — Submodule independence, JDL code hygiene, triết lý Multi-VPS.
