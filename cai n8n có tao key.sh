#!/bin/bash

# =============================================================
# KỊCH BẢN UPDATE N8N AN TOÀN
#  - Kiểm tra và tạo N8N_ENCRYPTION_KEY cố định nếu chưa có
#  - Kiểm tra mapping volume dữ liệu
#  - Backup .env, docker-compose.yml, và toàn bộ dữ liệu
#  - Update image và khởi động lại n8n với dữ liệu an toàn
# =============================================================

# ==================== THIẾT LẬP BIẾN ====================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

INSTALL_DIR="$HOME/n8n-caddy-stack"
ENV_FILE="$INSTALL_DIR/.env"
N8N_DATA_DIR="$INSTALL_DIR/n8n-data"      # Sửa đường dẫn nếu volume bên trái là nơi khác

TAG="${1:-latest}" # Có thể truyền tag version (mặc định: latest)

set -e

echo -e "${GREEN}BẮT ĐẦU QUY TRÌNH CẬP NHẬT N8N AN TOÀN${NC}"

# ==================== 1. KIỂM TRA THƯ MỤC CÀI ĐẶT ====================
if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}Lỗi: Không tìm thấy thư mục cài đặt tại ${INSTALL_DIR}.${NC}"
    exit 1
fi
cd "$INSTALL_DIR"

# ==================== 2. KIỂM TRA HOẶC TẠO ENCRYPTION_KEY ====================
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Không tìm thấy file .env – sẽ tạo mới.${NC}"
    touch "$ENV_FILE"
fi
if ! grep -q "^N8N_ENCRYPTION_KEY=" "$ENV_FILE"; then
    KEY=$(openssl rand -base64 32)
    echo -e "${YELLOW}Chưa có N8N_ENCRYPTION_KEY, sẽ tạo tự động:${NC}"
    echo "N8N_ENCRYPTION_KEY=$KEY" >> "$ENV_FILE"
    echo -e "${GREEN}Đã sinh KEY và thêm vào $ENV_FILE${NC}"
    echo "→ Lưu lại KEY này ở nơi an toàn: $KEY"
else
    KEY=$(grep "^N8N_ENCRYPTION_KEY=" "$ENV_FILE" | cut -d= -f2-)
    echo -e "${GREEN}Đã xác nhận ENCRYPTION_KEY cố định: $KEY${NC}"
fi

# ==================== 3. KIỂM TRA VOLUME MAPPING DỮ LIỆU ====================
if ! grep -q "/home/node/.n8n" docker-compose.yml; then
    echo -e "${RED}Không tìm thấy mapping data volume cho /home/node/.n8n${NC}"
    echo "Vui lòng kiểm tra docker-compose.yml – nếu update tiếp sẽ có nguy cơ mất workflow!"
    exit 1
fi

# ==================== 4. SAO LƯU DỮ LIỆU CỰC NHANH ====================
BACKUP_DIR="$HOME/n8n_backups/backup-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp docker-compose.yml "$BACKUP_DIR/docker-compose.yml"
cp "$ENV_FILE" "$BACKUP_DIR/.env"
if [ -d "$N8N_DATA_DIR" ]; then
    tar czf "$BACKUP_DIR/n8n-data.tgz" -C "$(dirname $N8N_DATA_DIR)" "$(basename $N8N_DATA_DIR)"
    echo -e "${GREEN}Đã BACKUP dữ liệu data n8n vào $BACKUP_DIR${NC}"
else
    echo -e "${YELLOW}Không tìm thấy thư mục $N8N_DATA_DIR (volume mount tùy chỉnh?), kiểm tra lại!${NC}"
fi

# ==================== 5. CẬP NHẬT IMAGE & UP CONTAINER ====================
echo -e "${YELLOW}Đang cập nhật image n8n:${TAG} trong docker-compose.yml...${NC}"
sed -i "s|image: n8nio/n8n:.*|image: n8nio/n8n:${TAG}|g" docker-compose.yml
echo -e "${YELLOW}Bắt đầu pull và khởi động lại n8n...${NC}"
docker compose pull n8n
docker compose up -d

# ==================== 6. DỌN DẸP IMAGE CŨ (KHI KHÔNG CẦN ROLLBACK) ====================
docker image prune -f

echo -e "${GREEN}CẬP NHẬT – BACKUP – KIỂM TRA KEY TẤT CẢ ĐÃ HOÀN TẤT! 🚀${NC}"
echo -e "${GREEN}KEY encryption: $KEY${NC}"
echo -e "${YELLOW}Đã backup toàn bộ config tại $BACKUP_DIR. Đường dẫn data: $N8N_DATA_DIR${NC}"
