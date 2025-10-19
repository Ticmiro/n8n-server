#!/bin/bash

#-------------------------------------------------
# KỊCH BẢN UPDATE N8N AN TOÀN - KHÔNG SINH KEY MỚI
# Dành cho hệ thống đã cài đặt với key cố định
#-------------------------------------------------

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="$HOME/n8n-caddy-stack"
ENV_FILE="$INSTALL_DIR/.env"
DOCKER_COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
N8N_DATA_DIR="$INSTALL_DIR/n8n-data"      # chỉnh lại nếu bạn đổi cấu trúc volume

TAG="${1:-1.45.1}"  # Có thể truyền tag version tại command line, mặc định: 1.45.1

set -e

echo -e "${GREEN}BẮT ĐẦU QUY TRÌNH UPDATE N8N AN TOÀN!${NC}"

# --- 1. KIỂM TRA THƯ MỤC CÀI ĐẶT ---
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}Lỗi: Không tìm thấy thư mục cài đặt tại ${INSTALL_DIR}.${NC}"
    exit 1
fi
cd "$INSTALL_DIR"

# --- 2. KIỂM TRA KEY VÀ CẢNH BÁO NGƯỜI DÙNG ---
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Không tìm thấy file .env! KHÔNG UPDATE nếu chưa phục hồi đúng N8N_ENCRYPTION_KEY.${NC}"
    exit 1
fi
if ! grep -q "^N8N_ENCRYPTION_KEY=" "$ENV_FILE"; then
    echo -e "${RED}CHƯA có N8N_ENCRYPTION_KEY trong .env! KHÔNG ĐƯỢC UPDATE nếu không có key chính gốc. Hãy phục hồi đúng file .env từ bản cài đặt gốc.${NC}"
    exit 1
fi
KEY=$(grep "^N8N_ENCRYPTION_KEY=" "$ENV_FILE" | cut -d= -f2-)
echo -e "${GREEN}KEY hiện tại dùng để giải mã credentials: $KEY${NC}"

# --- 3. KIỂM TRA VOLUME MAPPING ---
if ! grep -q "/home/node/.n8n" docker-compose.yml; then
    echo -e "${RED}Không tìm thấy mapping volume cho /home/node/.n8n! Chưa backup thì không được update (có thể mất workflows).${NC}"
    exit 1
fi

# --- 4. BACKUP ĐẦY ĐỦ TRƯỚC KHI UPDATE ---
BACKUP_DIR="$HOME/n8n_backups/backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp docker-compose.yml "$BACKUP_DIR/"
cp "$ENV_FILE" "$BACKUP_DIR/"
if [ -d "$N8N_DATA_DIR" ]; then
    tar czf "$BACKUP_DIR/n8n-data.tgz" -C "$(dirname $N8N_DATA_DIR)" "$(basename $N8N_DATA_DIR)"
    echo -e "${GREEN}Đã backup workflows/credentials/data vào $BACKUP_DIR${NC}"
else
    echo -e "${YELLOW}KHÔNG tìm thấy thư mục $N8N_DATA_DIR! Hãy xác nhận lại volume hoặc cấu hình.${NC}"
fi

# --- 5. CẬP NHẬT IMAGE VÀ RESTART DỊCH VỤ ---
echo -e "${YELLOW}Ghi lại image version mới trong docker-compose.yml...${NC}"
sed -i "s|image: n8nio/n8n:.*|image: n8nio/n8n:${TAG}|g" docker-compose.yml
echo -e "${YELLOW}Đang pull và restart n8n...${NC}"
docker compose pull n8n
docker compose up -d

# --- 6. DỌN DẸP IMAGE CŨ (TÙY CHỌN) ---
docker image prune -f

echo -e "${GREEN}CẬP NHẬT HOÀN TẤT! KEY encryption không đổi, backup đủ. Có thể khôi phục lại bất cứ lúc nào qua backup tại $BACKUP_DIR${NC}"
