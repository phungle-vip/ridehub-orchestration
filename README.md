# RideHub Infrastructure Orchestration (IaC & Automation)

Thư mục điều phối tập trung toàn bộ hạ tầng đám mây (Cloudflare), tự động hóa triển khai máy chủ (Ansible) và môi trường giả lập Multi-VPS (Mock).

---

## 📁 Cấu Trúc Thư Mục

```text
infra/orchestration/
│
├── terraform/                     # ☁️ Quản lý Cloudflare qua Infrastructure as Code
│   ├── versions.tf                # Khai báo Provider Cloudflare >= 4.40
│   ├── variables.tf               # Biến đầu vào: tokens, account_id, zone_id, domain
│   ├── main.tf                    # Tạo Tunnels, 12 DNS CNAMEs, 5 Zero Trust Apps
│   ├── outputs.tf                 # Xuất TUNNEL_TOKEN cho Ansible
│   ├── terraform.tfvars.example   # File mẫu biến môi trường Cloudflare
│   └── .gitignore
│
└── ansible/                       # ⚙️ Tự động hóa & Điều phối Multi-VPS
    ├── ansible.cfg                # Cấu hình Ansible
    ├── inventory.ini              # Khai báo máy chủ (Mock hoặc VPS Thật)
    ├── site.yml                   # Playbook chính điều phối toàn bộ
    ├── group_vars/all.yml         # Biến môi trường dùng chung
    ├── roles/                     # Các vai trò điều phối:
    │   ├── common/                # Kiểm tra OS, Docker Engine, Docker Compose
    │   ├── mesh_network/          # Xác minh liên kết mạng TCP giữa các VPS
    │   ├── deploy_infra/          # Điều phối cụm vps-infra
    │   └── deploy_microservices/  # Điều phối cụm vps-microservices
    │
    └── mock/                      # 🖥️ Môi trường giả lập 2 VPS trên 1 máy chủ
        ├── Dockerfile.mock-vps    # Debian Trixie + OpenSSH + Docker CLI
        └── docker-compose.mock.yml# Tạo 2 Nodes (vps1: 2221, vps2: 2222)
```

---

## 🚀 Hướng Dẫn Sử Dụng Nhanh

### 1. Khởi động môi trường giả lập 2 VPS (Nếu test cục bộ):
```bash
cd infra/orchestration/ansible/mock
docker compose -f docker-compose.mock.yml up -d
```

### 2. Chạy Playbook điều phối:
```bash
cd infra/orchestration/ansible
ansible-playbook site.yml
```

### 3. Build Docker Images Cho Microservices (Maven Jib qua Terraform):
```bash
infra/orchestration/terraform/manage-cloudflare.sh --build-images
# Hoặc build riêng 1 service:
infra/orchestration/terraform/manage-cloudflare.sh --build-images gateway
```

### 4. Khi Triển Khai Trên VPS Thật:
Chi tiết quy trình chuẩn bị SSH, cài Docker, đồng bộ code & cấu hình mạng VPC/VPN xem tại:
👉 [**Cẩm Nang Triển Khai Trên 2 VPS Thật (REAL_VPS_GUIDE.md)**](file:///home/phungvip/ridehub/infra/orchestration/REAL_VPS_GUIDE.md)


