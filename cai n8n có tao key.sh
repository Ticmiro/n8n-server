#!/bin/bash

#------------------------------------------------------------------
# KỊCH BẢN CÀI ĐẶT N8N AN TOÀN - TỰ ĐỘNG TẠO ENCRYPTION KEY
# Tác giả: Ticmiro
#------------------------------------------------------------------

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="$HOME/n8n-caddy-stack"
ENV_FILE="$INSTALL_DIR/.env"
DOCKER_COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
N8N_DATA_DIR="$INSTALL_DIR/n8n-data"

set -e

echo -e "${GREEN}Chào mừng đến với kịch bản cài đặt an toàn cho n8n!${NC}"

#--- NHẬP THÔNG TIN CẦN THIẾT ---
echo -e "${YELLOW}Vui lòng cung cấp các thông tin cấu hình cần thiết:${NC}"
read -p "Nhập tên miền bạn sẽ sử dụng cho n8n (vd: n8n.yourdomain.com): " DOMAINNAME
read -p "Nhập email của bạn (dùng cho cảnh báo SSL): " EMAILADDRESS
read -p "Nhập tên user cho PostgreSQL (vd: n8nuser): " POSTGRESUSER
read -s -p "Nhập mật khẩu cho PostgreSQL User: " POSTGRESPASSWORD
echo ""
read -p "Nhập tên database cho PostgreSQL (vd: n8ndb): " POSTGRESDB

if [ -z "$DOMAINNAME" ] || [ -z "$EMAILADDRESS" ] || [ -z "$POSTGRESUSER" ] || [ -z "$POSTGRESPASSWORD" ] || [ -z "$POSTGRESDB" ]; then
    echo -e "${RED}Lỗi: Tất cả các trường thông tin là bắt buộc!${NC}"
    exit 1
fi

mkdir -p "$INSTALL_DIR"

#--- TẠO FILE .env VÀ SINH N8N_ENCRYPTION_KEY AN TOÀN ---
if [ ! -f "$ENV_FILE" ]; then
    touch "$ENV_FILE"
fi

# Ghi các biến cơ bản vào .env nếu chưa có
grep -qxF "POSTGRESUSER=$POSTGRESUSER" "$ENV_FILE" || echo "POSTGRESUSER=$POSTGRESUSER" >> "$ENV_FILE"
grep -qxF "POSTGRESPASSWORD=$POSTGRESPASSWORD" "$ENV_FILE" || echo "POSTGRESPASSWORD=$POSTGRESPASSWORD" >> "$ENV_FILE"
grep -qxF "POSTGRESDB=$POSTGRESDB" "$ENV_FILE" || echo "POSTGRESDB=$POSTGRESDB" >> "$ENV_FILE"
grep -qxF "DOMAINNAME=$DOMAINNAME" "$ENV_FILE" || echo "DOMAINNAME=$DOMAINNAME" >> "$ENV_FILE"

# Sinh N8N_ENCRYPTION_KEY đúng chuẩn, chỉ 1 lần duy nhất
if ! grep -q "^N8N_ENCRYPTION_KEY=" "$ENV_FILE"; then
    KEY=$(openssl rand -base64 32)
    echo "N8N_ENCRYPTION_KEY=$KEY" >> "$ENV_FILE"
    echo -e "${GREEN}Đã sinh N8N_ENCRYPTION_KEY = $KEY (và ghi vào $ENV_FILE)${NC}"
    echo -e "${YELLOW}HÃY LƯU KEY NÀY ra nơi an toàn để tránh mất credentials khi update/migrate!${NC}"
else
    KEY=$(grep "^N8N_ENCRYPTION_KEY=" "$ENV_FILE" | cut -d= -f2-)
    echo -e "${GREEN}Đã tồn tại N8N_ENCRYPTION_KEY: $KEY${NC}"
fi

#--- TẠO FILE docker-compose.yml ---
cat > "$DOCKER_COMPOSE_FILE" <<EOF
version: "3.7"
services:
  caddy:
    image: caddy:latest
    container_name: caddyreverseproxy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile
      - caddydata:/data
      - caddyconfig:/config
    networks:
      - n8nnetwork

  postgres:
    image: postgres:15
    container_name: n8npostgresdb
    restart: always
    environment:
      - POSTGRES_USER=\${POSTGRESUSER}
      - POSTGRES_PASSWORD=\${POSTGRESPASSWORD}
      - POSTGRES_DB=\${POSTGRESDB}
    volumes:
      - ./postgres-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRESUSER} -d \${POSTGRESDB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - n8nnetwork

  n8n:
    image: n8nio/n8n:1.45.1
    container_name: n8nservice
    restart: always
    user: root
    ports:
      - "127.0.0.1:5678:5678"
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=\${POSTGRESDB}
      - DB_POSTGRESDB_USER=\${POSTGRESUSER}
      - DB_POSTGRESDB_PASSWORD=\${POSTGRESPASSWORD}
      - N8N_HOST=\${DOMAINNAME}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      - NODE_ENV=production
      - WEBHOOK_URL=https://\${DOMAINNAME}
      - TZ=Asia/Ho_Chi_Minh
    volumes:
      - ./n8n-data:/home/node/.n8n
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - n8nnetwork

networks:
  n8nnetwork:
    driver: bridge

volumes:
  caddydata:
  caddyconfig:
  postgres-data:
  n8n-data:
EOF

#--- KHỞI ĐỘNG DỊCH VỤ ---
echo -e "${YELLOW}Đang khởi tạo các container Docker...${NC}"
docker compose -f "$DOCKER_COMPOSE_FILE" up -d

echo -e "${GREEN}CÀI ĐẶT HOÀN TẤT - N8N đã sẵn sàng!${NC}"
echo -e "${YELLOW}Bạn có thể truy cập giao diện qua https://$DOMAINNAME${NC}"
echo -e "${GREEN}KEY giải mã đã lưu trong $ENV_FILE và được in phía trên. Nhớ backup KEY này!${NC}"
