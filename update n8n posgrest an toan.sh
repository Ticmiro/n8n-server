#!/bin/bash

#------------------------------------------------------------------
# KỊCH BẢN UPDATE & BACKUP N8N (TƯƠNG THÍCH VỚI KỊCH BẢN v5)
# Tác giả: Ticmiro & Gemini
# Chức năng:
# - Tương thích với Docker Compose v2 (có dấu cách).
# - Tự động đọc cấu hình từ .env.
# - Backup database PostgreSQL và file cấu hình.
# - Kiểm tra N8N_ENCRYPTION_KEY.
#------------------------------------------------------------------

# --- Tiện ích ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- THÔNG TIN CẤU HÌNH ---
INSTALL_DIR="$HOME/n8n-caddy-stack"
ENV_FILE="$INSTALL_DIR/.env"
COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"

# --- Tự động đọc biến từ file .env ---
if [ -f "$ENV_FILE" ]; then
    # Đọc tất cả các biến trong .env và export chúng
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo -e "${RED}LỖI: Không tìm thấy file .env tại $ENV_FILE${NC}"
    exit 1
fi

# --- Sử dụng các biến đã được đọc từ file .env ---
PG_CONTAINER="n8n_postgres_db" # Tên container từ file docker-compose.yml
PG_USER="${POSTGRES_USER}"     # Đã tự động đọc từ .env
PG_DB="${POSTGRES_DB}"         # Đã tự động đọc từ .env

# --- Cấu hình backup ---
PG_BACKUP_FILE="n8n-pg-backup-$(date +%Y%m%d_%H%M%S).sql"
N8N_BACKUP_DIR="$HOME/n8n_backups/backup-$(date +%Y%m%d_%H%M%S)"

# Lấy tag phiên bản từ tham số đầu tiên, nếu không có thì dùng 'latest'
TAG="${1:-latest}"

# Dừng lại nếu có lỗi
set -e

echo -e "${GREEN}=== BẮT ĐẦU QUY TRÌNH BACKUP & UPDATE n8n (PostgreSQL) ===${NC}"
echo "Sẽ update lên phiên bản tag: ${YELLOW}${TAG}${NC}"

mkdir -p "$N8N_BACKUP_DIR"
cd "$INSTALL_DIR"

# --- BƯỚC 1: BACKUP CÁC FILE CẤU HÌNH ---
echo -e "${YELLOW}--> Đang backup file docker-compose.yml và .env...${NC}"
cp "$COMPOSE_FILE" "$N8N_BACKUP_DIR/"
cp "$ENV_FILE" "$N8N_BACKUP_DIR/"
echo -e "${GREEN}Backup file cấu hình hoàn tất.${NC}"

# --- BƯỚC 2: BACKUP DATABASE POSTGRESQL ---
echo -e "${YELLOW}--> Đang backup DATABASE PostgreSQL...${NC}"
if [ -z "$PG_USER" ] || [ -z "$PG_DB" ]; then
    echo -e "${RED}LỖI: Không thể đọc POSTGRES_USER hoặc POSTGRES_DB từ file .env.${NC}"
    exit 1
fi

sudo docker exec "$PG_CONTAINER" pg_dump -U "$PG_USER" "$PG_DB" > "$N8N_BACKUP_DIR/$PG_BACKUP_FILE"
echo -e "${GREEN}Backup DB thành công: $N8N_BACKUP_DIR/$PG_BACKUP_FILE${NC}"

# --- BƯỚC 3: KIỂM TRA N8N_ENCRYPTION_KEY ---
echo -e "${YELLOW}--> Đang kiểm tra N8N_ENCRYPTION_KEY...${NC}"
if [ -z "$N8N_ENCRYPTION_KEY" ]; then
  # Kịch bản v5 luôn tạo key này, nên nếu bị lỗi ở đây thì rất lạ
  echo -e "${RED}LỖI: File .env không có N8N_ENCRYPTION_KEY!${NC}"
  echo "Việc update sẽ thất bại và làm mất hết credentials nếu không có key này."
  exit 1
fi

echo -e "${GREEN}Đã tìm thấy N8N_ENCRYPTION_KEY. An toàn để tiếp tục.${NC}"

# --- BƯỚC 4: CẬP NHẬT FILE COMPOSE VÀ KHỞI ĐỘNG LẠI ---
echo -e "${YELLOW}--> Cập nhật image n8n lên tag: ${TAG}...${NC}"
sed -i -E "s|^([[:space:]]*)image: n8nio/n8n:.*|\1image: n8nio/n8n:${TAG}|g" "$COMPOSE_FILE"

echo -e "${YELLOW}--> Đang tải (pull) image n8n mới...${NC}"
# Sử dụng 'docker compose' (có dấu cách) và 'sudo'
sudo docker compose pull n8n

echo -e "${YELLOW}--> Khởi động lại các container với phiên bản mới...${NC}"
# Sử dụng 'docker compose' (có dấu cách) và 'sudo'
sudo docker compose up -d

# --- BƯỚC 5: DỌN DẸP ---
echo -e "${YELLOW}--> Dọn dẹp các image cũ không còn sử dụng...${NC}"
sudo docker image prune -f || true

echo -e "${GREEN}==================================================================${NC}"
echo -e "${GREEN}🚀 UPDATE HOÀN TẤT! 🚀${NC}"
echo "Hệ thống đã được cập nhật lên phiên bản ${YELLOW}${TAG}${NC}."
echo "Tất cả backup được lưu an toàn tại: ${GREEN}$N8N_BACKUP_DIR${NC}"
echo -e "${GREEN}==================================================================${NC}"