#!/usr/bin/env bash
# ==============================================================================
# Script Name : update_wps.sh
# Description : Remove older WPS Office and deploy latest .deb on Mint / Kubuntu
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERROR]${NC} $1"; }

# 1. Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
   log_err "Vui lòng chạy script với quyền sudo hoặc root: sudo bash $0"
   exit 1
fi

TEMP_DIR=$(mktemp -d /tmp/wps_update.XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT

log_info "Bắt đầu quy trình kiểm tra và nâng cấp WPS Office..."

# 2. Dừng các tiến trình WPS đang chạy để tránh lock file
log_info "Dừng các tiến trình WPS đang chạy ngầm..."
killall -9 wps wpp et wpspdf 2>/dev/null || true

# 3. Tìm và gỡ bỏ phiên bản WPS cũ
log_info "Kiểm tra và gỡ bỏ các bản WPS Office cũ..."

# Gỡ gói APT / DEB
if dpkg -l | grep -qE '^ii\s+(wps-office|wps-office-bin)'; then
    OLD_VER=$(dpkg -l | grep -E '^ii\s+wps-office' | awk '{print $3}' | head -n1)
    log_warn "Tìm thấy WPS Office (DEB) phiên bản cũ: $OLD_VER. Tiến hành gỡ bỏ..."
    apt-get remove --purge -y wps-office wps-office-bin 2>/dev/null || dpkg -P wps-office wps-office-bin 2>/dev/null || true
    apt-get autoremove -y
    log_success "Đã gỡ gói DEB cũ thành công."
else
    log_info "Không phát hiện gói DEB cũ nào trong apt/dpkg."
fi

# Gỡ gói Flatpak (nếu trước đó có cài qua Flathub/Software Center)
if command -v flatpak &>/dev/null && flatpak list | grep -qi "com.wps.Office"; then
    log_warn "Phát hiện bản Flatpak com.wps.Office, đang gỡ..."
    flatpak uninstall -y com.wps.Office 2>/dev/null || true
fi

# Gỡ gói Snap (nếu có)
if command -v snap &>/dev/null && snap list | grep -qi "wps-office"; then
    log_warn "Phát hiện bản Snap wps-office, đang gỡ..."
    snap remove wps-office 2>/dev/null || true
fi

# 4. Lấy link tải file DEB mới nhất
log_info "Đang dò tìm phiên bản DEB mới nhất từ máy chủ WPS..."

# Dò URL tải deb 64-bit từ trang linux.wps.cn
LATEST_URL=$(curl -sL https://linux.wps.cn | grep -oP 'https://[^\s"'\''<>]+wps-office[^\s"'\''<>]+\.deb' | head -n 1)

# Nếu không cào được URL động, dùng endpoint CDN chính thức bản 64-bit ổn định
if [[ -z "$LATEST_URL" ]]; then
    log_warn "Không thể tự động bóc tách link từ portal. Sử dụng URL CDN chính thức..."
    LATEST_URL="https://wdl1.pcfg.cache.wpscdn.com/wpsdl/wpsoffice/download/linux/11723/wps-office_11.1.0.11723.XA_amd64.deb"
fi

DEB_FILE="$TEMP_DIR/wps-office-latest.deb"
log_info "Tải bản mới từ: $LATEST_URL"

if command -v curl &>/dev/null; then
    curl -L --progress-bar -o "$DEB_FILE" "$LATEST_URL"
elif command -v wget &>/dev/null; then
    wget --show-progress -q -O "$DEB_FILE" "$LATEST_URL"
else
    apt-get update && apt-get install -y curl
    curl -L --progress-bar -o "$DEB_FILE" "$LATEST_URL"
fi

# 5. Cài đặt gói DEB mới và xử lý dependencies
log_info "Bắt đầu cài đặt bản WPS Office mới..."
dpkg -i "$DEB_FILE" || {
    log_warn "Xử lý thư viện phụ thuộc còn thiếu..."
    apt-get update
    apt-get install -f -y
}

# 6. Dọn dẹp MIME, Icon cache trên Desktop KDE Plasma / Cinnamon
log_info "Cập nhật Desktop database và Icon caches..."
update-desktop-database 2>/dev/null || true
update-mime-database /usr/share/mime 2>/dev/null || true
gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true

# 7. Kiểm tra xác nhận phiên bản sau cài đặt
NEW_VER=$(dpkg -l | grep -E '^ii\s+wps-office' | awk '{print $3}' | head -n1)
if [[ -n "$NEW_VER" ]]; then
    log_success "Hoàn tất! WPS Office đã được cập nhật lên phiên bản: $NEW_VER"
else
    log_err "Có lỗi xảy ra, không tìm thấy phiên bản cài đặt."
    exit 1
fi
