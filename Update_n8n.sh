#!/bin/bash

#------------------------------------------------------------------
# KỊCH BẢN CẬP NHẬT TỰ ĐỘNG N8N
# Tác giả: Ticmiro
# Chức năng:
# - Tự động cập nhật n8n lên phiên bản mới nhất cho một cài đặt
#   sử dụng Docker Compose.
# - An toàn, có sao lưu và tự động dọn dẹp.
#------------------------------------------------------------------

# --- Tiện ích ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Dừng lại ngay lập tức nếu có bất kỳ lệnh nào thất bại
set -e

echo -e "${GREEN}Chào mừng đến với kịch bản cập nhật tự động n8n!${NC}"
echo "------------------------------------------------------------------"

# --- BƯỚC 1: XÁC ĐỊNH THƯ MỤC CÀI ĐẶT ---
INSTALL_DIR="$HOME/n8n-caddy-stack"

if [ ! -d "$INSTALL_DIR" ]; then
    echo -e "${RED}Lỗi: Không tìm thấy thư mục cài đặt tại ${INSTALL_DIR}.${NC}"
    echo "Vui lòng đảm bảo bạn đã chạy kịch bản cài đặt trước đó."
    exit 1
fi

echo -e "${YELLOW}--> Đã tìm thấy thư mục cài đặt. Bắt đầu quá trình cập nhật...${NC}"
cd "$INSTALL_DIR"

# --- BƯỚC 2: SAO LƯU FILE CẤU HÌNH ---
echo "--> Tạo bản sao lưu cho docker-compose.yml..."
cp docker-compose.yml docker-compose.yml.bak-$(date +%Y%m%d_%H%M%S)
echo -e "${GREEN}Sao lưu thành công.${NC}"

# --- BƯỚC 3: KIỂM TRA VÀ THÊM VOLUME MAPPING CHO N8N ---
# Kiểm tra xem n8n service đã có volume mapping đúng chưa
if ! grep -q "volumes:" docker-compose.yml || ! grep -q "volumes:\n.*-.*.n8n" docker-compose.yml; then
    echo -e "${RED}Lỗi: Có thể thiếu 'volumes' mapping cho n8n. Dữ liệu của bạn có thể bị mất.${NC}"
    echo "Tự động thêm cấu hình volumes để bảo vệ dữ liệu."
    # Thêm volume mapping. Thư mục /root/n8n_data sẽ được tạo trên máy chủ
    sed -i '/n8n:/a\ \ \ \ \ \ \ \ volumes:\n\ \ \ \ \ \ \ \ \ \ - \/root\/n8n_data:\/home\/node\/.n8n' docker-compose.yml
    echo -e "${GREEN}Đã thêm volumes mapping thành công.${NC}"
fi

# --- BƯỚC 4: CẬP NHẬT IMAGE LÊN PHIÊN BẢN MỚI NHẤT ---
echo "--> Cập nhật image n8n thành 'latest' trong docker-compose.yml..."
# Lệnh sed này sẽ tìm dòng chứa 'image: n8nio/n8n' và thay thế tag phiên bản thành 'latest'
sed -i 's|image: n8nio/n8n:.*|image: n8nio/n8n:latest|g' docker-compose.yml
echo -e "${GREEN}Cập nhật file cấu hình thành công.${NC}"

# --- BƯỚC 5: TẢI VỀ VÀ KHỞI ĐỘNG LẠI ---
echo -e "${YELLOW}--> Tải về phiên bản n8n mới nhất... (Thao tác này có thể mất vài phút)${NC}"
sudo docker compose pull n8n

echo -e "${YELLOW}--> Dừng container cũ và khởi động container mới...${NC}"
sudo docker compose up -d

# --- BƯỚC 6: DỌN DẸP ---
echo "--> Dọn dẹp các image n8n cũ không còn được sử dụng..."
sudo docker image prune -f
echo -e "${GREEN}Dọn dẹp hoàn tất.${NC}"

# --- BƯỚC 7: HOÀN TẤT ---
echo "=================================================================="
echo -e "${GREEN}🚀 CẬP NHẬT HOÀN TẤT! 🚀${NC}"
echo "=================================================================="
echo ""
echo "n8n đã được cập nhật thành công lên phiên bản mới nhất."
echo "Dữ liệu (workflows, credentials, executions) của bạn đã được bảo toàn."
echo ""
echo "Để kiểm tra phiên bản mới, hãy truy cập vào n8n và xem ở góc dưới bên trái."
echo "=================================================================="
