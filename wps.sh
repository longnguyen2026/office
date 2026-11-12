#!/bin/bash
set -e

# Màu sắc hiển thị log
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# 1. Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Vui lòng chạy script bằng quyền sudo (sudo bash wps.sh)${NC}"
    exit 1
fi

echo -e "${CYAN}[INFO] Bắt đầu quy trình kiểm tra và nâng cấp WPS Office...${NC}"

# 2. Dừng các tiến trình WPS đang chạy ngầm
echo -e "${CYAN}[INFO] Dừng các tiến trình WPS đang chạy ngầm...${NC}"
killall -9 wps wpp et wpspdf wpscloudsvr 2>/dev/null || true

# 3. Gỡ bỏ triệt để mọi phiên bản WPS cũ (DEB, Snap, Flatpak)
echo -e "${CYAN}[INFO] Kiểm tra và gỡ bỏ các bản WPS Office cũ...${NC}"
if dpkg -l | grep -qw wps-office; then
    echo -e "${YELLOW}[INFO] Phát hiện gói DEB wps-office cũ, đang tiến hành gỡ bỏ...${NC}"
    apt-get purge -y wps-office 2>/dev/null || dpkg --purge --force-all wps-office 2>/dev/null || true
    apt-get autoremove -y 2>/dev/null || true
fi

if command -v snap >/dev/null 2>&1 && snap list 2>/dev/null | grep -qw wps-office; then
    snap remove wps-office 2>/dev/null || true
fi

if command -v flatpak >/dev/null 2>&1 && flatpak list 2>/dev/null | grep -q com.wps.Office; then
    flatpak uninstall -y com.wps.Office 2>/dev/null || true
fi

# 4. Dọn sạch file MIME lỗi rỗng gây kẹt dpkg
rm -f /usr/share/mime/packages/custom-wps-office.xml
update-mime-database /usr/share/mime 2>/dev/null || true

# 5. Lấy link tải WPS Office bản 12 mới nhất
echo -e "${CYAN}[INFO] Đang tìm link tải WPS Office bản mới nhất...${NC}"
FALLBACK_URL="https://pubwps-wps365-obs.wpscdn.cn/download/Linux/29183/wps-office_12.1.2.29183.AK.preread.sw.Personal_806791_amd64.deb"
LATEST_URL=$(curl -fsSL --connect-timeout 10 "https://linux.wps.cn/" | grep -oE 'https://[^"]+_amd64\.deb' | head -n 1 || true)

if [ -n "$LATEST_URL" ]; then
    DOWNLOAD_URL="$LATEST_URL"
else
    echo -e "${YELLOW}[WARN] Không lấy được link động, dùng bản ổn định 12.1.2.29183...${NC}"
    DOWNLOAD_URL="$FALLBACK_URL"
fi

TMP_DEB="/tmp/wps-office-latest.deb"
rm -f "$TMP_DEB"
echo -e "${CYAN}[INFO] Đang tải từ: $DOWNLOAD_URL${NC}"
curl -fL --progress-bar "$DOWNLOAD_URL" -o "$TMP_DEB"

# Kiểm tra tính hợp lệ của file DEB vừa tải
if ! dpkg-deb -I "$TMP_DEB" >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] File DEB tải về bị lỗi hoặc không hợp lệ!${NC}"
    rm -f "$TMP_DEB"
    exit 1
fi
echo -e "${GREEN}[SUCCESS] Tải thành công file DEB hợp lệ.${NC}"

# 6. Cài đặt WPS Office mới
echo -e "${CYAN}[INFO] Bắt đầu cài đặt WPS Office mới...${NC}"
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y "$TMP_DEB"
rm -f "$TMP_DEB"

# 7. Cấu hình mặc định giao diện tiếng Anh (en_US) cho người dùng hiện tại
REAL_USER=${SUDO_USER:-$USER}
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
if [ -n "$USER_HOME" ] && [ -d "$USER_HOME" ]; then
    mkdir -p "$USER_HOME/.config/Kingsoft"
    cat << 'EOF' > "$USER_HOME/.config/Kingsoft/Office.conf"
[General]
languages=en_US
EOF
    chown -R "$REAL_USER:$REAL_USER" "$USER_HOME/.config/Kingsoft"
fi

# 8. Chạy script vá lỗi định dạng MIME upload Google Drive
echo -e "${CYAN}[INFO] Áp dụng bản vá MIME upload Google Drive (fix-upload-drive.sh)...${NC}"
curl -fsSL "https://raw.githubusercontent.com/longnguyen2026/office/main/fix-upload-drive.sh" | bash || true

# 9. Cập nhật lại cache hệ thống
update-desktop-database /usr/share/applications 2>/dev/null || true
update-mime-database /usr/share/mime 2>/dev/null || true

echo -e "${GREEN}[SUCCESS] Hoàn tất cài đặt và cấu hình WPS Office!${NC}"
