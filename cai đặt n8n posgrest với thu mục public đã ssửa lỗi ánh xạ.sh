#!/bin/bash

#------------------------------------------------------------------
# KỊCH BẢN CÀI ĐẶT TỰ ĐỘNG HOÀN CHỈNH (v5.1 - Đã thêm Volume cho n8n)
# Tác giả: Ticmiro & Gemini
# Chức năng:
# - Cài đặt Docker Compose v2 (plugin, có dấu cách) để
#   khắc phục triệt để lỗi 'KeyError: ContainerConfig'.
# - (MỚI) Ánh xạ 'public_media' vào cả Caddy (để public)
#   và n8n (để node 'Write File' có thể truy cập).
# - Tự động tạo và lưu N8N_ENCRYPTION_KEY.
# - Cài đặt n8n, PostgreSQL, Caddy (Reverse Proxy & SSL).
# - Mở cổng PostgreSQL 5432 cho kết nối bên ngoài.
#------------------------------------------------------------------

# --- Tiện ích ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Dừng lại ngay lập tức nếu có bất kỳ lệnh nào thất bại
set -e

echo -e "${GREEN}Chào mừng đến với kịch bản cài đặt hoàn chỉnh cho n8n! (Phiên bản v5.1)${NC}"
echo -e "${GREEN}Tác giả: Ticmiro & Gemini${NC}"
echo "------------------------------------------------------------------"

# --- BƯỚC 1: HỎI THÔNG TIN NGƯỜI DÙNG ---
echo -e "${YELLOW}Vui lòng cung cấp các thông tin cấu hình cần thiết:${NC}"

read -p "Nhập tên miền bạn sẽ sử dụng cho n8n (ví dụ: n8n.yourdomain.com): " DOMAIN_NAME
read -p "Nhập email của bạn (dùng cho thông báo gia hạn SSL): " EMAIL_ADDRESS
read -p "Nhập tên cho PostgreSQL User (ví dụ: n8n_user): " POSTGRES_USER
read -s -p "Nhập mật khẩu MẠNH cho PostgreSQL User: " POSTGRES_PASSWORD
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
sudo apt-get install -y ca-certificates curl git openssl

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
    
    # Chỉ cài đặt Docker engine
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
    
    echo -e "${GREEN}--> Cài đặt Docker Engine hoàn tất.${NC}"
else
    echo -e "${GREEN}--> Docker Engine đã được cài đặt. Bỏ qua bước này.${NC}"
fi

# --- BƯỚC 4: CÀI ĐẶT DOCKER COMPOSE v2 (PLUGIN) ---
echo -e "${YELLOW}--> Cài đặt Docker Compose v2 (plugin, có dấu cách)...${NC}"
if ! docker compose version &> /dev/null
then
    echo -e "${YELLOW}--> Docker Compose v2 chưa được cài đặt. Bắt đầu cài đặt thủ công...${NC}"
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$LATEST_COMPOSE_VERSION" ]; then
        echo -e "${RED}Lỗi: Không thể tìm thấy phiên bản Docker Compose mới nhất. Sử dụng phiên bản ổn định mặc định.${NC}"
        LATEST_COMPOSE_VERSION="v2.27.1"
    fi
    echo "Phiên bản Docker Compose mới nhất là: $LATEST_COMPOSE_VERSION"

    DOCKER_COMPOSE_DEST="/usr/libexec/docker/cli-plugins"
    sudo mkdir -p $DOCKER_COMPOSE_DEST
    sudo curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o $DOCKER_COMPOSE_DEST/docker-compose
    sudo chmod +x $DOCKER_COMPOSE_DEST/docker-compose
    
    if ! docker compose version &> /dev/null
    then
        echo -e "${RED}LỖI: Cài đặt Docker Compose v2 thất bại.${NC}"
        exit 1
    else
        echo -e "${GREEN}--> Cài đặt Docker Compose v2 thành công.${NC}"
    fi
else
    echo -e "${GREEN}--> Docker Compose v2 đã được cài đặt. Bỏ qua bước này.${NC}"
    docker compose version
fi


# --- BƯỚC 5: CẤU HÌNH DOCKER VÀ TƯỜNG LỬA ---
echo -e "${YELLOW}--> Cấu hình Docker để ưu tiên IPv4...${NC}"
sudo cat > /etc/docker/daemon.json << EOF
{
  "ipv6": false
}
EOF
sudo systemctl restart docker

echo -e "${YELLOW}--> Cấu hình tường lửa UFW...${NC}"
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

echo -e "${RED}==================================================================${NC}"
echo -e "${RED}CẢNH BÁO BẢO MẬT: Mở cổng 5432 (PostgreSQL) ra Internet.${NC}"
echo -e "${YELLOW}Hãy đảm bảo bạn đã SỬ DỤNG MẬT KHẨU RẤT MẠNH cho database.${NC}"
echo -e "${RED}==================================================================${NC}"
sudo ufw allow 5432/tcp

sudo ufw --force enable

# --- BƯỚC 6: TẠO FILE CẤU HÌNH VÀ TRIỂN KHAI DOCKER ---
INSTALL_DIR="$HOME/n8n-caddy-stack"
echo -e "${YELLOW}--> Tạo các file cấu hình tại ${INSTALL_DIR}...${NC}"

mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/public_media"
echo -e "${GREEN}--> Đã tạo thư mục media tại ${INSTALL_DIR}/public_media${NC}"

cd "$INSTALL_DIR"

echo -e "${YELLOW}--> Đang tạo N8N_ENCRYPTION_KEY...${NC}"
ENCRYPTION_KEY=$(openssl rand -hex 32)
if [ -z "$ENCRYPTION_KEY" ]; then
    echo -e "${RED}Lỗi: Không thể tạo ENCRYPTION_KEY.${NC}"
    exit 1
fi
echo -e "${GREEN}Đã tạo Key mã hóa thành công.${NC}"

# Tạo file .env
cat > .env << EOF
# Thông tin đăng nhập cho PostgreSQL
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}

# Múi giờ cho n8n
TZ=Asia/Ho_Chi_Minh

# Khóa mã hóa cho credentials (Đã được tạo tự động)
N8N_ENCRYPTION_KEY=${ENCRYPTION_KEY}
EOF

# Tạo file Caddyfile
cat > Caddyfile << EOF
${DOMAIN_NAME} {
    handle_path /public/* {
        root * /var/www/public
        file_server
    }
    handle {
        reverse_proxy n8n:5678
    }
}
EOF

# Tạo file docker-compose.yml
# (THAY ĐỔI: Thêm volume 'public_media' vào dịch vụ 'n8n')
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
      # Ánh xạ vào Caddy để public
      - ./public_media:/var/www/public
    networks:
      - n8n_network

  postgres:
    image: postgres:15
    container_name: n8n_postgres_db
    restart: always
    ports:
      - "5432:5432"
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
    networks:
      - n8n_network

  n8n:
    # Bạn có thể đổi 'latest' thành phiên bản cụ thể nếu muốn, ví dụ: n8nio/n8n:1.45.1
    image: n8nio/n8n:latest
    container_name: n8n_service
    restart: always
    user: "root"
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
      - TZ=\${TZ}
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      # Thêm các gói node mở rộng nếu cần, ví dụ:
      # - NODES_INCLUDE=@n8n/n8n-nodes-langchain
    volumes:
      - ./n8n-data:/home/node/.n8n
      # --- ĐÃ THÊM: Ánh xạ vào n8n để ghi file ---
      - ./public_media:/home/node/public_media
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - n8n_network

networks:
  n8n_network:
    driver: bridge

volumes:
  caddy_data: {}
  caddy_config: {}
  postgres-data: {}
  n8n-data: {}
EOF

echo -e "${YELLOW}--> Khởi chạy các dịch vụ (Caddy, n8n, PostgreSQL)...${NC}"
echo "Bước này sẽ tự động tải image về, có thể mất vài phút."
sudo docker compose up -d

# --- BƯỚC 7: HOÀN TẤT ---
echo "=================================================================="
echo -e "${GREEN}🚀 CÀI ĐẶT HOÀN TẤT! 🚀${NC}"
echo "=================================================================="
echo ""
echo "Bạn có thể truy cập n8n ngay bây giờ tại: ${GREEN}https://${DOMAIN_NAME}${NC}"
echo -e "Khóa mã hóa (N8N_ENCRYPTION_KEY) đã được tạo và lưu tại: ${GREEN}${INSTALL_DIR}/.env${NC}"
echo ""
echo -e "${YELLOW}--- MEDIA CÔNG KHAI ---${NC}"
echo "Để LƯU file từ n8n, hãy dùng đường dẫn: ${GREEN}/home/node/public_media/ten_file.png${NC}"
echo "Để TRUY CẬP file qua web, hãy dùng URL: ${GREEN}https://${DOMAIN_NAME}/public/ten_file.png${NC}"
echo ""
echo -e "${RED}--- THÔNG TIN & CẢNH BÁO DATABASE ---${NC}"
echo "Database PostgreSQL của bạn hiện đang mở ra Internet qua cổng 5432."
echo "Host: ${GREEN}${DOMAIN_NAME}${NC} (hoặc IP của VPS)"
echo "Port: ${GREEN}5432${NC}"
echo "User: ${GREEN}${POSTGRES_USER}${NC}"
echo "Database: ${GREEN}${POSTGRES_DB}${NC}"
echo ""
echo "Để xem log của hệ thống, chạy lệnh: ${YELLOW}cd ${INSTALL_DIR} && sudo docker compose logs -f${NC}"
echo "=================================================================="