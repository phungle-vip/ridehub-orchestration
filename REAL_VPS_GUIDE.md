# 🌐 HƯỚNG DẪN TRIỂN KHAI RIDEHUB TRÊN 2 VPS VẬT LÝ THẬT (MULTI-VPS DEPLOYMENT)

> **Mục tiêu**: Hướng dẫn chi tiết từng bước đưa toàn bộ hệ sinh thái **RideHub** từ môi trường giả lập (Mock) lên **2 VPS vật lý thực tế** (Cloud VPS từ DigitalOcean, Hetzner, AWS, Linode, OVH, v.v.).
> **Tuân thủ**: Triết lý kiến trúc trong `AGENTS.md` (Độc lập Submodule, Database per Service, Mạng định tuyến Multi-VPS, Bảo mật Zero Trust).

---

## 1. Mô Hình Phân Bổ 2 VPS Thực Tế

```text
[ Người Dùng & Dev Local ]
         │
         ▼ (HTTPS qua Cloudflare Zero Trust / Cloudflare Tunnel / WARP Client)
 ┌───────────────────────────────────────┐
 │               CLOUDFLARE              │
 │  - DNS Records: *.phungvip.io.vn      │
 │  - Zero Trust Access: Kafdrop, SSH    │
 │  - WARP Private Routes: 172.18 / 172.19│
 └──────────────────┬────────────────────┘
                    │
        ┌───────────┴───────────┐
        ▼                       ▼
┌───────────────────┐   ┌───────────────────┐
│       VPS 1       │   │       VPS 2       │
│  (HẠ TẦNG TRUNG   │◄─►│  (MICROSERVICES & │
│       TÂM)        │   │    DATABASES)     │
├───────────────────┤   ├───────────────────┤
│ - Keycloak (OIDC) │   │ - API Gateway     │
│ - Kafka (Kraft)   │   │ - ms_booking      │
│ - HashiCorp Consul│   │ - ms_user         │
│ - HashiCorp Vault │   │ - ms_route        │
│ - Redis Cache     │   │ - ms_promotion    │
│ - Prometheus/Loki │   │ - 4 x MySQL DBs   │
│ - Grafana / Nginx │   │ - Docker API      │
│ - Reposilite      │   │ - Metrics Agents  │
└───────────────────┘   └───────────────────┘
```

---

## 2. Yêu Cầu Cấu Hình Phần Cứng & Mạng (Prerequisites)

### A. Cấu Hình Phần Cứng Khuyến Nghị
| Máy chủ | CPU | RAM | Ổ Cứng (SSD/NVMe) | Hệ Điều Hành |
|---|:---:|:---:|:---:|:---:|
| **VPS 1 (Infra Hub)** | 2 vCPU | **4 GB - 8 GB** | 40 GB - 60 GB | Ubuntu 22.04/24.04 LTS hoặc Debian 12/13 |
| **VPS 2 (Microservices)** | 4 vCPU | **8 GB - 16 GB** | 60 GB - 80 GB | Ubuntu 22.04/24.04 LTS hoặc Debian 12/13 |

*(Lưu ý: VPS 2 chạy 5 ứng dụng Java Spring Boot + 4 instances MySQL nên khuyến nghị tối thiểu 8GB RAM để vận hành mượt mà).*

### B. Mạng Nội Bộ (Private Network / Layer 4 Mesh)
Để Microservices trên VPS 2 kết nối với Kafka (port 9093) và Redis (port 6379) trên VPS 1, có thể sử dụng một trong 3 phương án sau:

1. **Phương án 1 (Khuyến Nghị Cao Nhất: Cloudflare-First với Zero Trust Private Network)**:
   - **Ưu điểm vượt trội**: Hoàn toàn **miễn phí**, không cần mở bất kỳ cổng Inbound firewall nào trên VPS 1 & VPS 2, tận dụng hạ tầng Cloudflare sẵn có của RideHub.
   - **Nguyên lý**:
     - **Trên VPS 1 (Infra Hub)**: Cloudflare Tunnel đăng ký Private Network Route cho subnet Docker `172.18.0.0/16` (đã được cấu hình tự động trong Terraform [`infra/orchestration/terraform/main.tf`](file:///home/phungvip/ridehub/infra/orchestration/terraform/main.tf)).
     - **Trên VPS 2 (Microservices)**: Cài đặt client `cloudflare-warp` ở chế độ headless (chạy ngầm không giao diện):
       ```bash
       # Cài đặt cloudflare-warp trên VPS 2 (Ubuntu/Debian)
       curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
       echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/cloudflare-warp.list
       apt update && apt install cloudflare-warp -y

       # Đăng ký và kết nối WARP vào mạng Zero Trust của tổ chức
       warp-cli registration new
       warp-cli mode warp
       warp-cli connect
       ```
     - Sau khi kết nối, VPS 2 có thể ping và gọi trực tiếp tới các dịch vụ trên VPS 1 qua IP Docker nội bộ:
       - Kafka SSL: `172.18.0.x:9093`
       - Redis: `172.18.0.x:6379`
       - MySQL: `172.18.0.x:3306`

2. **Phương án 2: Mạng Riêng Của Nhà Cung Cấp (Cùng Cloud Provider / Cùng VPC)**:
   - Nếu cả 2 VPS thuê cùng một nhà cung cấp (Hetzner, DigitalOcean, Vultr, AWS, OVH):
     - Bật tính năng **Private Networking (VPC)** trên Dashboard của Cloud Provider.
     - Sử dụng Private IP nội bộ do nhà cung cấp cấp phát (ví dụ: VPS 1 là `10.0.0.10`, VPS 2 là `10.0.0.20`).
     - Tốc độ đạt tối đa theo băng thông mạng LAN vật lý của Datacenter.

3. **Phương án 3: Tailscale Mesh VPN hoặc WireGuard (Dự phòng độc lập)**:
   - Dành cho trường hợp 2 VPS đặt ở 2 nhà cung cấp khác nhau mà không muốn dùng WARP:
     - Cài Tailscale trên cả 2 node: `curl -fsSL https://tailscale.com/install.sh | sh`
     - Chạy `tailscale up` trên cả 2 máy và đăng nhập tài khoản.
     - Lấy địa chỉ IP Tailscale (dải `100.x.y.z`) làm IP mạng nội bộ mã hóa an toàn giữa 2 node.

---

## 3. Quy Trình Chuẩn Bị Trước Khi Chạy Ansible (Pre-flight Checklist)

### Bước 1: Cấu hình SSH Key Truy Cập Không Cần Mật Khẩu
Từ máy cá nhân (nơi bạn chạy lệnh Ansible), copy SSH Public Key vào cả 2 VPS:
```bash
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<PUBLIC_IP_VPS_1>
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@<PUBLIC_IP_VPS_2>
```
Kiểm tra thử `ssh root@<PUBLIC_IP_VPS_1>` xem đã vào được trực tiếp mà không hỏi mật khẩu chưa.

### Bước 2: Cài Đặt Docker & Docker Compose Trên 2 VPS
Chạy lệnh cài đặt nhanh trên cả 2 VPS (nếu là VPS mới tinh):
```bash
curl -fsSL https://get.docker.com | sh
systemctl enable --now docker
```

### Bước 3: Đồng Bộ Thư Mục Dự Án Lên 2 VPS
Tạo thư mục làm việc `/opt/ridehub` trên cả 2 VPS và copy code tương ứng:
- **Trên VPS 1**: Cần thư mục `infra/vps-infra`:
  ```bash
  ssh root@<PUBLIC_IP_VPS_1> "mkdir -p /opt/ridehub/infra"
  rsync -avzP --exclude '.git' infra/vps-infra root@<PUBLIC_IP_VPS_1>:/opt/ridehub/infra/
  ```
- **Trên VPS 2**: Cần thư mục `infra/vps-microservices`:
  ```bash
  ssh root@<PUBLIC_IP_VPS_2> "mkdir -p /opt/ridehub/infra"
  rsync -avzP --exclude '.git' infra/vps-microservices root@<PUBLIC_IP_VPS_2>:/opt/ridehub/infra/
  ```

### Bước 4: Đồng Bộ File Bí Mật `.env`
Vì file `.env` không được đưa lên Git vì lý do bảo mật, bạn copy file `.env` đã cấu hình lên đúng vị trí:
```bash
scp infra/vps-infra/.env root@<PUBLIC_IP_VPS_1>:/opt/ridehub/infra/vps-infra/.env
scp infra/vps-microservices/.env root@<PUBLIC_IP_VPS_2>:/opt/ridehub/infra/vps-microservices/.env
```

---

## 4. Cấu Hình Ansible Inventory Cho VPS Thật

Mở file [`infra/orchestration/ansible/inventory.ini`](file:///home/phungvip/ridehub/infra/orchestration/ansible/inventory.ini) và cập nhật thông tin máy chủ thật:

```ini
[vps_infra]
vps1 ansible_host=<PUBLIC_IP_VPS_1> ansible_port=22 ansible_user=root ansible_ssh_private_key_file=~/.ssh/id_ed25519 internal_ip=<PRIVATE_IP_VPS_1>

[vps_microservices]
vps2 ansible_host=<PUBLIC_IP_VPS_2> ansible_port=22 ansible_user=root ansible_ssh_private_key_file=~/.ssh/id_ed25519 internal_ip=<PRIVATE_IP_VPS_2>

[all_vps:children]
vps_infra
vps_microservices
```

Cập nhật file [`infra/orchestration/ansible/group_vars/all.yml`](file:///home/phungvip/ridehub/infra/orchestration/ansible/group_vars/all.yml):
```yaml
domain: "phungvip.io.vn"
timezone: "Asia/Ho_Chi_Minh"
infra_internal_ip: "<PRIVATE_IP_VPS_1>"
ms_internal_ip: "<PRIVATE_IP_VPS_2>"
workspace_dir: "/opt/ridehub"
```

---

## 5. Quy Trình Thực Thi 1 Chạm (Execution)

### Bước 1: Build Docker Images Cho Microservices (Maven Jib)
Trước khi khởi chạy các container nghiệp vụ, cần build ảnh container cho 5 service:
```bash
infra/orchestration/terraform/manage-cloudflare.sh --build-images
```
Lệnh này sẽ kích hoạt Maven Jib build độc lập từng submodule thành các image Docker sẵn sàng trên Docker daemon (`gateway:latest`, `ms_user:latest`, `ms_booking:latest`, `ms_route:latest`, `ms_promotion:latest`).

### Bước 2: Chạy Ansible Điều Phối Toàn Diện
```bash
cd infra/orchestration/ansible
ansible-playbook site.yml
```
Ansible sẽ tự động:
1. **Giai đoạn 0**: Kiểm tra và đồng bộ Cloudflare Zero Trust qua Terraform.
2. **Giai đoạn 1**: Kiểm tra chuẩn hóa OS, Docker và Docker Compose trên cả 2 VPS.
3. **Giai đoạn 2**: Kiểm tra liên kết mạng TCP giữa 2 VPS thông qua `internal_ip`.
4. **Giai đoạn 3**: Kích hoạt cụm hạ tầng trung tâm (`vps-infra`) trên VPS 1.
5. **Giai đoạn 4**: Kích hoạt cụm cơ sở dữ liệu MySQL và Microservices trên VPS 2.

---

## 6. Kiểm Tra & Vận Hành Sau Triển Khai

1. **Kiểm tra trạng thái Cloudflare**:
   ```bash
   infra/orchestration/terraform/manage-cloudflare.sh --status
   ```
2. **Truy cập nội bộ an toàn qua WARP**:
   Bật Cloudflare WARP trên máy cá nhân để kết nối trực tiếp vào IP nội bộ của container:
   - Truy cập MySQL VPS 2: `172.19.0.x:3306`
   - Truy cập Redis VPS 1: `172.18.0.x:6379`
   - Truy cập Kafka VPS 1: `172.18.0.x:9093`
3. **Truy cập các Dashboard Quản Trị**:
   - Grafana: `https://grafana.phungvip.io.vn`
   - Kafka UI: `https://kafdrop.phungvip.io.vn` (Bảo vệ bởi Keycloak OIDC)
   - Keycloak Admin: `https://keycloak.phungvip.io.vn`
   - Consul: `https://consul.phungvip.io.vn`
   - Vault: `https://vault.phungvip.io.vn`
