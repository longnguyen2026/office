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

# 5. Tải gói cài đặt WPS Office từ Google Drive
GDRIVE_ID="1jqo0D8A7snDaypXO2iPt1ceugEwlxk94"
TMP_DEB="/tmp/wps-office-latest.deb"
rm -f "$TMP_DEB"

echo -e "${CYAN}[INFO] Đang tải gói cài đặt WPS Office từ Google Drive...${NC}"

# Cài gdown nếu chưa có để vượt qua trang cảnh báo file lớn (>100MB) của Google Drive
if ! command -v gdown >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq python3-pip >/dev/null 2>&1 || true
    pip3 install --break-system-packages -q gdown 2>/dev/null || pip3 install -q gdown 2>/dev/null || true
fi

if command -v gdown >/dev/null 2>&1; then
    gdown "https://drive.google.com/uc?id=${GDRIVE_ID}" -O "$TMP_DEB"
else
    # Phương án dự phòng bằng curl nếu máy không cài được gdown
    curl -fL -c /tmp/gcookie "https://drive.usercontent.google.com/download?id=${GDRIVE_ID}&export=download&confirm=t" -o "$TMP_DEB"
    rm -f /tmp/gcookie
fi

# Kiểm tra tính hợp lệ của file DEB vừa tải
if ! dpkg-deb -I "$TMP_DEB" >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] File tải từ Google Drive không hợp lệ (kiểm tra lại quyền chia sẻ công khai của file)!${NC}"
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
curl -fsSL "https://raw.githubusercontent.com/longnguyen2026/office/main/fix-upload-drive.sh?nocache=$RANDOM" | bash -s || true

# ==============================================================================
# [BỔ SUNG 1] CHỈ VÁ LỖI BỘ GÕ NẾU MÁY ĐANG DÙNG IBUS-BAMBOO (BỎ QUA FCITX5/VDKEY)
# ==============================================================================
IS_FCITX5=false
if pgrep -x "fcitx5" >/dev/null 2>&1 || dpkg -l 2>/dev/null | grep -qE '^ii\s+(fcitx5|vdkey|fcitx5-ngosen|fcitx5-lotus)'; then
    IS_FCITX5=true
fi

if [ "$IS_FCITX5" = false ] && (dpkg -l 2>/dev/null | grep -qw "ibus-bamboo" || pgrep -x "ibus-daemon" >/dev/null 2>&1); then
    echo -e "${CYAN}[INFO] Phát hiện bộ gõ IBus (ibus-bamboo), đang cấu hình tương thích cho WPS Office...${NC}"
    
    # 1. Chèn biến môi trường IBus vào file khởi chạy nếu là shell script
    for app in wps et wpp wpspdf; do
        TARGET_BIN=$(readlink -f "/usr/bin/$app" 2>/dev/null || true)
        if [ -f "$TARGET_BIN" ] && head -n 1 "$TARGET_BIN" | grep -q "^#!"; then
            if ! grep -q "QT_IM_MODULE" "$TARGET_BIN"; then
                sed -i '2i export XMODIFIERS="@im=ibus"\nexport QT_IM_MODULE="ibus"' "$TARGET_BIN"
            fi
        fi
    done

    # 2. Khởi động lại IBus cho user hiện tại để nhận diện ngay không cần reboot
    if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
        USER_ID=$(id -u "$REAL_USER")
        if [ -S "/run/user/$USER_ID/bus" ]; then
            sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" ibus restart 2>/dev/null || true
        fi
    fi
else
    echo -e "${CYAN}[INFO] Hệ thống đang dùng Fcitx5/VDKey hoặc không dùng IBus, bỏ qua bước vá IBus.${NC}"
fi

# ==============================================================================
# [BỔ SUNG 2] CẬP NHẬT TOÀN BỘ CACHE HỆ THỐNG & ICON THEME (THAY THẾ BƯỚC 9 CŨ)
# Vị trí: Thay thế cho Bước 9 cũ để sửa lỗi icon bánh răng trên Linux Mint
# ==============================================================================
echo -e "${CYAN}[INFO] Cập nhật lại cache ứng dụng, MIME và toàn bộ Icon theme...${NC}"
update-desktop-database /usr/share/applications 2>/dev/null || true
update-mime-database /usr/share/mime 2>/dev/null || true

# Quét làm mới tất cả thư mục icon (Mint-Y, hicolor, WhiteSur...) thay vì chỉ hicolor
for theme_dir in /usr/share/icons/*; do
    [ -d "$theme_dir" ] && gtk-update-icon-cache -f -t "$theme_dir" 2>/dev/null || true
done

# ==============================================================================
# [BỔ SUNG 3] KHỞI ĐỘNG LẠI BỘ GÕ CHO USER HIỆN TẠI ĐỂ GÕ ĐƯỢC NGAY KHÔNG CẦN REBOOT
# Vị trí: Cuối cùng, ngay trước thông báo hoàn tất
# ==============================================================================
if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
    USER_ID=$(id -u "$REAL_USER")
    if [ -S "/run/user/$USER_ID/bus" ]; then
        sudo -u "$REAL_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" ibus restart 2>/dev/null || true
    fi
fi

echo -e "${GREEN}[SUCCESS] Hoàn tất cài đặt và cấu hình WPS Office!${NC}"
