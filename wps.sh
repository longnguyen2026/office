#!/usr/bin/env bash
# ==============================================================================
# Script Name : wps.sh
# Target OS   : Linux Mint / Kubuntu / Debian / Ubuntu
# ==============================================================================

set -eo pipefail

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
   log_err "Vui lòng chạy script với quyền sudo: curl -fsSL <url> | sudo bash"
   exit 1
fi

TEMP_DIR=$(mktemp -d /tmp/wps_update.XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT

log_info "Bắt đầu quy trình kiểm tra và nâng cấp WPS Office..."

# 2. Đóng tiến trình đang chạy
log_info "Dừng các tiến trình WPS đang chạy ngầm..."
killall -9 wps wpp et wpspdf 2>/dev/null || true

# 3. Dọn dẹp MIME lỗi tồn đọng
if [[ -f "/usr/share/mime/packages/custom-wps-office.xml" ]]; then
    log_warn "Phát hiện file MIME bị lỗi, tiến hành dọn dẹp..."
    rm -f /usr/share/mime/packages/custom-wps-office.xml
fi

# 4. Gỡ bỏ bản WPS cũ
log_info "Kiểm tra và gỡ bỏ các bản WPS Office cũ..."
if dpkg -l | grep -qE '^ii\s+(wps-office|wps-office-bin)'; then
    OLD_VER=$(dpkg -l | grep -E '^ii\s+wps-office' | awk '{print $3}' | head -n1)
    log_warn "Tìm thấy WPS Office cũ: $OLD_VER. Tiến hành gỡ bỏ..."
    apt-get remove --purge -y wps-office wps-office-bin 2>/dev/null || dpkg -P wps-office wps-office-bin 2>/dev/null || true
    apt-get autoremove -y
    log_success "Đã gỡ gói DEB cũ thành công."
fi

if command -v flatpak &>/dev/null && flatpak list | grep -qi "com.wps.Office"; then
    log_warn "Gỡ bỏ bản Flatpak..."
    flatpak uninstall -y com.wps.Office 2>/dev/null || true
fi

if command -v snap &>/dev/null && snap list | grep -qi "wps-office"; then
    log_warn "Gỡ bỏ bản Snap..."
    snap remove wps-office 2>/dev/null || true
fi

# 5. Danh sách link tải DEB chính thức (tự động thử lần lượt)
DEB_URLS=(
    "https://wdl1.pcfg.cache.wpscdn.com/wpsdl/wpsoffice/download/linux/11723/wps-office_11.1.0.11723.XA_amd64.deb"
    "https://wdl1.pcfg.cache.wpscdn.com/wpsdl/wpsoffice/download/linux/11664/wps-office_11.1.0.11664.XA_amd64.deb"
    "https://wps-linux-personal.wpscdn.cn/wps/download/ep/Linux2023/29183/wps-office_12.1.2.29183.AK.preread.sw.Personal_806791_amd64.deb"
)

DEB_FILE="$TEMP_DIR/wps-office.deb"
DOWNLOAD_SUCCESS=false
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

log_info "Đang tải gói cài đặt DEB..."

for URL in "${DEB_URLS[@]}"; do
    log_info "Thử tải từ: $URL"
    rm -f "$DEB_FILE"
    
    curl -fL -A "$UA" \
         -H "Referer: https://linux.wps.cn/" \
         --retry 2 --retry-delay 2 \
         --progress-bar -o "$DEB_FILE" "$URL" || continue

    # Kiểm tra magic bytes của định dạng Debian package (ar archive: !<arch>)
    if [[ -f "$DEB_FILE" ]] && head -c 8 "$DEB_FILE" | grep -q '!<arch>'; then
        DOWNLOAD_SUCCESS=true
        log_success "Tải thành công file DEB hợp lệ."
        break
    else
        log_warn "Tệp tải về không đúng định dạng Debian package (có thể bị chặn bởi CDN). Thử link tiếp theo..."
    fi
done

if [[ "$DOWNLOAD_SUCCESS" != true ]]; then
    log_err "Không thể tải file DEB hợp lệ từ các máy chủ. Vui lòng kiểm tra lại kết nối mạng."
    exit 1
fi

# 6. Cài đặt gói DEB mới và tự xử lý dependencies
log_info "Bắt đầu cài đặt bản WPS Office..."
dpkg -i "$DEB_FILE" || {
    log_warn "Đang cấu hình và bổ sung thư viện thiếu..."
    apt-get update
    apt-get install -f -y
}

# 7. Cập nhật cache hệ thống
log_info "Cập nhật Desktop database và Icon cache..."
update-desktop-database 2>/dev/null || true
update-mime-database /usr/share/mime 2>/dev/null || true
gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true

# 8. Xác nhận
NEW_VER=$(dpkg -l | grep -E '^ii\s+wps-office' | awk '{print $3}' | head -n1)
if [[ -n "$NEW_VER" ]]; then
    log_success "Hoàn tất! WPS Office đã được cài đặt thành công: $NEW_VER"
else
    log_err "Cài đặt thất bại, không tìm thấy phiên bản cài đặt."
    exit 1
fi

# ==============================================================================
# # 9. TỰ ĐỘNG FIX LỖI UPLOAD GOOGLE DRIVE (MIME TYPE XLSX / DOCX)
# ==============================================================================
echo ""
log_info "Áp dụng bản vá MIME type cho Google Drive..."
if curl -fsSL "https://raw.githubusercontent.com/longnguyen2026/office/main/fix-upload-drive.sh" | bash; then
    log_success "Đã cấu hình và cập nhật MIME database thành công!"
else
    log_warn "Không thể tự động fix upload Drive (kiểm tra lại kết nối mạng)."
fi
