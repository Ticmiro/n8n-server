#!/bin/bash

#------------------------------------------------------------------
# KỊCH BẢN CÀI ĐẶT TỰ ĐỘNG HOÀN THIỆN
# Tác giả: Ticmiro
# Chức năng:
# - Cài đặt n8n với PostgreSQL.
# - Tự động hóa cài đặt Nginx Reverse Proxy.
# - Tự động hóa cấu hình HTTPS với Let's Encrypt.
#------------------------------------------------------------------

# --- Tiện ích ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Dừng lại ngay lập tức nếu có lỗi
set -e

echo -e "${GREEN}Chào mừng đến với kịch bản cài đặt n8n!${NC}"
echo -e "${GREEN}Tác giả: Ticmiro  ${NC}"
echo "------------------------------------------------------------------"

# --- 1. THU THẬP CÁC THÔNG TIN CẤU HÌNH ---
echo -e "${YELLOW}Vui lòng cung cấp các thông tin cấu hình cần thiết:${NC}"

read -p "Nhập tên miền bạn sẽ sử dụng cho n8n (ví dụ: n8n.yourdomain.com): " DOMAIN_NAME
read -p "Nhập email của bạn (dùng cho thông báo gia hạn SSL): " EMAIL_ADDRESS
read -p "Nhập tên cho PostgreSQL User (ví dụ: n8n_user): " POSTGRES_USER
read -s -p "Nhập mật khẩu cho PostgreSQL User: " POSTGRES_PASSWORD
echo
read -p "Nhập tên cho PostgreSQL Database (ví dụ: n8n_db): " POSTGRES_DB

# Kiểm tra xem người dùng đã nhập thông tin chưa
if [ -z "$DOMAIN_NAME" ] || [ -z "$EMAIL_ADDRESS" ] || [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_PASSWORD" ] || [ -z "$POSTGRES_DB" ]; then
  echo -e "${RED}Lỗi: Tất cả các trường thông tin không được để trống.${NC}"
  exit 1
fi

echo ""
echo "--- Cấu hình sẽ được cài đặt cho tên miền: $DOMAIN_NAME ---"
echo ""

# --- 2. CÀI ĐẶT CÁC GÓI HỆ THỐNG CẦN THIẾT ---
echo -e "${YELLOW}--> Cập nhật hệ thống và cài đặt Nginx, Certbot...${NC}"
sudo apt-get update
sudo apt-get install -y nginx certbot python3-certbot-nginx git

# --- 3. CẤU HÌNH TƯỜNG LỬA (UFW) ---
echo -e "${YELLOW}--> Cấu hình tường lửa UFW...${NC}"
sudo ufw allow ssh       # Cho phép kết nối SSH (cổng 22)
sudo ufw allow 'Nginx Full' # Cho phép kết nối HTTP (80) và HTTPS (443)
sudo ufw --force enable  # Bật tường lửa mà không cần hỏi

# --- 4. TẠO FILE CẤU HÌNH VÀ CÀI ĐẶT DOCKER ---
N8N_DIR="$HOME/.n8n-postgres"
echo -e "${YELLOW}--> Tạo các file cấu hình tại ${N8N_DIR}...${NC}"

mkdir -p "$N8N_DIR"
cd "$N8N_DIR"

# Tạo file .env
cat > .env << EOF
# Thông tin đăng nhập cho PostgreSQL
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
EOF

# Tạo file docker-compose.yml
cat > docker-compose.yml << EOF
version: '3.7'

services:
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
    ports:
      - "127.0.0.1:5678:5678"
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
EOF

echo -e "${YELLOW}--> Khởi chạy n8n và PostgreSQL...${NC}"
sudo docker compose up -d

# --- 5. CẤU HÌNH NGINX VÀ LẤY CHỨNG CHỈ SSL ---
echo -e "${YELLOW}--> Cấu hình Nginx và tự động lấy chứng chỉ SSL...${NC}"

# Tạo file cấu hình Nginx ban đầu (chỉ HTTP)
sudo cat > /etc/nginx/sites-available/$DOMAIN_NAME << EOF
server {
    listen 80;
    server_name $DOMAIN_NAME;
    location / {
        proxy_pass http://localhost:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

# Kích hoạt cấu hình Nginx
sudo ln -sfn /etc/nginx/sites-available/$DOMAIN_NAME /etc/nginx/sites-enabled/$DOMAIN_NAME
sudo nginx -t
sudo systemctl restart nginx

# Chạy Certbot ở chế độ không tương tác
sudo certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos -m "$EMAIL_ADDRESS" --redirect

# --- 6. HOÀN TẤT ---
echo "=================================================================="
echo -e "${GREEN}🚀 CÀI ĐẶT HOÀN TẤT! 🚀${NC}"
echo "=================================================================="
echo ""
echo "Bạn có thể truy cập n8n ngay bây giờ tại: ${GREEN}https://${DOMAIN_NAME}${NC}"
echo "Thông tin database của bạn đã được lưu trong file: ${GREEN}${N8N_DIR}/.env${NC}"
echo ""
echo "Để xem log của hệ thống, chạy lệnh: ${YELLOW}cd ${N8N_DIR} && sudo docker compose logs -f${NC}"
echo "=================================================================="