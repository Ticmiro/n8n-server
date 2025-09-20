#!/bin/bash

#------------------------------------------------------------------
# KỊCH BẢN CẬP NHẬT TỰ ĐỘNG N8N (Tối ưu cho cài đặt của bạn)
# Tác giả: Ticmiro & Gemini (Dựa trên file "cai n8n sqlife.sh")
# Chức năng:
# - Cập nhật n8n lên phiên bản mới nhất cho cài đặt Docker Compose của bạn.
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

# --- BƯỚC 3: KIỂM TRA TÍNH AN TOÀN CỦA DỮ LIỆU ---
# Kiểm tra xem volume mapping đã tồn tại trong docker-compose.yml chưa.
if grep -q "\- \.\/n8n-data:\/home\/node\/.n8n" docker-compose.yml; then
    echo -e "${GREEN}--> Đã tìm thấy cấu hình volume mapping. Dữ liệu của bạn được an toàn.${NC}"
else
    echo -e "${RED}Lỗi: Không tìm thấy 'volume mapping' cho n8n trong file docker-compose.yml.${NC}"
    echo -e "Dữ liệu của bạn có thể bị mất. Vui lòng kiểm tra lại file cấu hình."
    echo "Kịch bản đã dừng để đảm bảo an toàn cho dữ liệu của bạn."
    exit 1
fi

# --- BƯỚC 4: CẬP NHẬT IMAGE LÊN PHIÊN BẢN MỚI NHẤT ---
echo "--> Cập nhật image n8n thành 'latest' trong docker-compose.yml..."
# Lệnh sed này sẽ tìm dòng chứa 'docker.n8n.io/n8nio/n8n' và thay thế tag thành 'latest'
sed -i 's|image: docker.n8n.io/n8nio/n8n:.*|image: docker.n8n.io/n8nio/n8n:latest|g' docker-compose.yml
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
echo "Toàn bộ dữ liệu (workflows, credentials, executions) của bạn đã được bảo toàn."
echo ""
echo "Để kiểm tra phiên bản mới, hãy truy cập vào n8n và xem ở góc dưới bên trái."
echo "=================================================================="