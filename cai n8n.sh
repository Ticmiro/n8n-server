#!/bin/bash

#------------------------------------------------------------------
# KỊCH BẢN CÀI ĐẶT TỰ ĐỘNG HOÀN THIỆN
# Tác giả: Ticmiro & Gemini
# Chức năng:
# - Cài đặt n8n với PostgreSQL trên một VPS trống.
# - Tự động hóa cài đặt Docker, Reverse Proxy và HTTPS với Caddy.
#------------------------------------------------------------------

# --- Tiện ích ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Dừng lại ngay lập tức nếu có lỗi
set -e

echo -e "${GREEN}Chào mừng đến với kịch bản cài đặt tự động n8n!${NC}"
echo -e "${GREEN}Tác giả: Ticmiro & Gemini${NC}"
echo "------------------------------------------------------------------"

# --- BƯỚC 1: HỎI THÔNG TIN NGƯỜI DÙNG ---
echo -e "${YELLOW}Vui lòng cung cấp các thông tin cấu hình cần thiết:${NC}"

read -p "Nhập tên miền bạn sẽ sử dụng cho n8n (ví dụ: n8n.yourdomain.com): " DOMAIN_NAME
read -p "Nhập email của bạn (dùng cho thông báo gia hạn SSL): " EMAIL_ADDRESS
read -p "Nhập tên cho PostgreSQL User (ví dụ: n8n_user): " POSTGRES_USER
read -s -p "Nhập mật khẩu cho PostgreSQL User: " POSTGRES_PASSWORD
echo
read -p "Nhập tên cho PostgreSQL Database (ví dụ: n8n_db): " POSTGRES_DB

if [ -z "$DOMAIN_NAME" ] || [ -z "$EMAIL_ADDRESS" ] || [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_PASSWORD" ] || [ -z "$POSTGRES_DB" ]; then
  echo -e "${RED}Lỗi: Tất cả các trường thông tin không được để trống.${NC}"
  exit 1
fi

echo ""
echo "--- Cấu hình sẽ được cài đặt cho tên miền: $DOMAIN_NAME ---"
echo ""

# --- BƯỚC 2: CÀI ĐẶT CÁC GÓI HỆ THỐNG CẦN THIẾT ---
echo -e "${YELLOW}--> Cập nhật hệ thống và cài đặt các gói cơ bản...${NC}"
sudo apt-get update
sudo apt-get install -y ca-certificates curl git

# --- BƯỚC 3: KIỂM TRA VÀ CÀI ĐẶT DOCKER ---
if ! command -v docker &> /dev/null
then
    echo -e "${YELLOW}--> Docker chưa được cài đặt. Bắt đầu cài đặt Docker...${NC}"
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    echo -e "${GREEN}--> Cài đặt Docker hoàn tất.${NC}"
else
    echo -e "${GREEN}--> Docker đã được cài đặt. Bỏ qua bước này.${NC}"
fi

# --- BƯỚC 4: CẤU HÌNH TƯỜNG LỬA (UFW) ---
echo -e "${YELLOW}--> Cấu hình tường lửa UFW...${NC}"
sudo ufw allow ssh       # Cho phép kết nối SSH (cổng 22)
sudo ufw allow 80/tcp    # Cho phép HTTP cho Caddy
sudo ufw allow 443/tcp   # Cho phép HTTPS cho Caddy
sudo ufw --force enable  # Bật tường lửa mà không cần hỏi

# --- BƯỚC 5: TẠO FILE CẤU HÌNH VÀ TRIỂN KHAI DOCKER ---
INSTALL_DIR="$HOME/n8n-caddy-stack"
echo -e "${YELLOW}--> Tạo các file cấu hình tại ${INSTALL_DIR}...${NC}"

mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Tạo file .env
cat > .env << EOF
# Thông tin đăng nhập cho PostgreSQL
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
EOF

# Tạo file Caddyfile
cat > Caddyfile << EOF
${DOMAIN_NAME} {
    reverse_proxy n8n:5678
}
EOF

# Tạo file docker-compose.yml
cat > docker-compose.yml << EOF
version: '3.7'

services:
  caddy:
    image: caddy:latest
    container_name: caddy_reverse_proxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config

  postgres:
    image: postgres:15
    container_name: n8n_postgres_db
    restart: always
    environment:
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
      - POSTGRES_DB=\${POSTGRES_DB}
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5

  n8n:
    image: n8nio/n8n
    container_name: n8n_service
    restart: always
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=\${POSTGRES_DB}
      - DB_POSTGRESDB_USER=\${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=\${POSTGRES_PASSWORD}
      - N8N_HOST=${DOMAIN_NAME}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://${DOMAIN_NAME}/
    volumes:
      - ./n8n-data:/home/node/.n8n
    depends_on:
      postgres:
        condition: service_healthy

volumes:
  caddy_data:
  caddy_config:
  postgres-data:
  n8n-data:
EOF

echo -e "${YELLOW}--> Khởi chạy các dịch vụ (Caddy, n8n, PostgreSQL)...${NC}"
sudo docker compose up -d

# --- BƯỚC 6: HOÀN TẤT ---
echo "=================================================================="
echo -e "${GREEN}🚀 CÀI ĐẶT HOÀN TẤT! 🚀${NC}"
echo "=================================================================="
echo ""
echo "Caddy sẽ tự động lấy và cấu hình SSL cho bạn trong vài phút tới."
echo "Bạn có thể truy cập n8n ngay bây giờ tại: ${GREEN}https://${DOMAIN_NAME}${NC}"
echo "Thông tin database của bạn đã được lưu trong file: ${GREEN}${INSTALL_DIR}/.env${NC}"
echo ""
echo "Để xem log của hệ thống, chạy lệnh: ${YELLOW}cd ${INSTALL_DIR} && sudo docker compose logs -f${NC}"
echo "=================================================================="
