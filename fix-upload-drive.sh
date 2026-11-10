#!/usr/bin/env bash
# ==============================================================================
# Script: fix-wps-mime-gdrive.sh
# Mô tả: Sửa lỗi Google Drive không nhận diện .xlsx, .docx, .pptx do WPS Office
#        ghi đè MIME type chuẩn trên Linux (application/wps-office.*)
# Tương thích: Ubuntu, Debian, Mint, Fedora, Arch Linux
# ==============================================================================

set -euo pipefail

MODE="fix"
TARGET_USERS=""

# Khai báo MIME chuẩn OpenXML và MS Office
declare -A STANDARD_MIMES=(
    ["xlsx"]="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    ["docx"]="application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    ["pptx"]="application/vnd.openxmlformats-officedocument.presentationml.presentation"
    ["xls"]="application/vnd.ms-excel"
    ["doc"]="application/msword"
    ["ppt"]="application/vnd.ms-powerpoint"
)

log()  { printf '\033[0;32m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[0;33m[WARN]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

usage() {
    cat <<EOF
Cách sử dụng:
  sudo bash $0 [TÙY CHỌN]

Tùy chọn:
  --check               Chỉ kiểm tra cấu hình hệ thống và user, không chỉnh sửa
  --users=u1,u2         Chỉ định danh sách user cần fix (mặc định: tự quét tất cả user UID >= 1000)
  -h, --help            Hiển thị trợ giúp này
EOF
    exit 0
}

# Xử lý tham số
for arg in "$@"; do
    case "${arg}" in
        --check) MODE="check" ;;
        --users=*) TARGET_USERS="${arg#--users=}" ;;
        -h|--help) usage ;;
        *) warn "Tham số không xác định: ${arg}" ;;
    esac
done

[ "$(id -u)" -eq 0 ] || die "Script yêu cầu quyền root/sudo để cập nhật /usr/share/mime và skel."

# Tự động lấy danh sách user nếu không chỉ định
get_user_list() {
    if [ -n "${TARGET_USERS}" ]; then
        IFS=',' read -r -a USERS <<< "${TARGET_USERS}"
        echo "${USERS[@]}"
    else
        awk -F: '$3 >= 1000 && $3 < 60000 && $6 ~ /^\/home/ {print $1}' /etc/passwd
    fi
}

USER_LIST=($(get_user_list))

# 1. FIX SYSTEM LEVEL
fix_system() {
    log ">>> [1/2] Đang xử lý cấu hình hệ thống (/usr/share/mime)..."

    # Xóa package MIME độc quyền của WPS
    rm -f /usr/share/mime/packages/wps-office-*.xml \
          /usr/share/mime/packages/wps-office*.xml 2>/dev/null || true
    rm -f /usr/share/mime/application/wps-office.*.xml 2>/dev/null || true

    # Đặt template mặc định cho user mới tạo sau này
    mkdir -p /etc/skel/.config/Kingsoft
    cat > /etc/skel/.config/Kingsoft/Office.conf <<'EOF'
[6.0]
common\do_not_detect_file_association_while_startup=true
EOF
    chmod 0644 /etc/skel/.config/Kingsoft/Office.conf

    if command -v update-mime-database >/dev/null 2>&1; then
        update-mime-database /usr/share/mime
        log "Đã biên dịch lại cơ sở dữ liệu MIME toàn hệ thống."
    else
        die "Không tìm thấy lệnh update-mime-database. Hãy cài đặt gói shared-mime-info."
    fi
}

# Đảm bảo file cấu hình WPS không tự đổi association
ensure_kingsoft_conf() {
    local home="$1"
    local conf="${home}/.config/Kingsoft/Office.conf"
    mkdir -p "${home}/.config/Kingsoft"

    if [ ! -f "${conf}" ]; then
        printf '%s\n' '[6.0]' 'common\do_not_detect_file_association_while_startup=true' > "${conf}"
    else
        if ! grep -q 'do_not_detect_file_association_while_startup=true' "${conf}"; then
            if grep -q '^\[6\.0\]' "${conf}"; then
                sed -i '/^\[6\.0\]/a common\\do_not_detect_file_association_while_startup=true' "${conf}"
            else
                printf '%s\n' '[6.0]' 'common\do_not_detect_file_association_while_startup=true' '' | cat - "${conf}" > "${conf}.tmp"
                mv "${conf}.tmp" "${conf}"
            fi
        fi
    fi
}

# 2. FIX PER-USER LEVEL
fix_users() {
    log ">>> [2/2] Đang xử lý cấu hình theo từng tài khoản người dùng..."
    local u home owner

    for u in "${USER_LIST[@]}"; do
        id "${u}" >/dev/null 2>&1 || { warn "Bỏ qua: User '${u}' không tồn tại"; continue; }
        home="$(getent passwd "${u}" | cut -d: -f6)"
        [ -d "${home}" ] || { warn "Bỏ qua: Thư mục home '${home}' không tồn tại"; continue; }
        owner="$(stat -c '%U:%G' "${home}" 2>/dev/null || echo "${u}:${u}")"

        # Tắt tiến trình WPS nếu đang chạy để tránh ghi đè lại file config
        pkill -u "${u}" -f 'wps|et|wpp|prometheus|kingsoft' 2>/dev/null || true

        ensure_kingsoft_conf "${home}"

        # Dọn dẹp MIME override của WPS trong thư mục local user
        rm -f "${home}/.local/share/mime/packages/Override.xml" 2>/dev/null || true
        rm -f "${home}/.local/share/mime/packages/"*wps* 2>/dev/null || true
        rm -f "${home}/.local/share/mime/application/wps-office.*.xml" 2>/dev/null || true

        if [ -d "${home}/.local/share/mime" ]; then
            if command -v update-mime-database >/dev/null 2>&1; then
                sudo -u "${u}" -H update-mime-database "${home}/.local/share/mime" >/dev/null 2>&1 || true
            fi
        fi

        # Phân quyền lại đúng cho user
        chown -R "${owner}" "${home}/.config/Kingsoft" 2>/dev/null || true
        [ -d "${home}/.local/share/mime" ] && chown -R "${owner}" "${home}/.local/share/mime" 2>/dev/null || true

        log "Đã xử lý xong cho user: ${u}"
    done
}

# KIỂM TRA TOÀN DIỆN
verify_status() {
    log "=== BẮT ĐẦU KIỂM TRA (VERIFY) ==="
    local bad=0

    # 1. Check globs2 hệ thống
    if grep -q 'wps-office' /usr/share/mime/globs2 2>/dev/null; then
        warn "Hệ thống: Vẫn còn ánh xạ WPS trong /usr/share/mime/globs2!"
        bad=1
    else
        log "Hệ thống: globs2 chuẩn, không còn định dạng wps-office.*."
    fi

    # 2. Check per-user
    local u home
    for u in "${USER_LIST[@]}"; do
        id "${u}" >/dev/null 2>&1 || continue
        home="$(getent passwd "${u}" | cut -d: -f6)"
        [ -d "${home}" ] || continue

        # Tạo file test tạm để query trực tiếp bằng xdg-mime
        local tmp_xlsx="${home}/.test_probe.xlsx"
        local tmp_docx="${home}/.test_probe.docx"
        touch "${tmp_xlsx}" "${tmp_docx}"
        chown "${u}:${u}" "${tmp_xlsx}" "${tmp_docx}" 2>/dev/null || true

        local got_xlsx got_docx
        got_xlsx="$(sudo -u "${u}" -H xdg-mime query filetype "${tmp_xlsx}" 2>/dev/null || true)"
        got_docx="$(sudo -u "${u}" -H xdg-mime query filetype "${tmp_docx}" 2>/dev/null || true)"
        rm -f "${tmp_xlsx}" "${tmp_docx}"

        if [[ "${got_xlsx}" == *"wps-office"* ]] || [[ "${got_docx}" == *"wps-office"* ]]; then
            warn "User ${u}: Vẫn trả về MIME WPS (xlsx=${got_xlsx}, docx=${got_docx})"
            bad=1
        elif [[ "${got_xlsx}" == "${STANDARD_MIMES[xlsx]}" ]] && [[ "${got_docx}" == "${STANDARD_MIMES[docx]}" ]]; then
            log "User ${u}: MIME chuẩn OpenXML chuẩn xác 100%!"
        else
            log "User ${u}: Trả về (${got_xlsx} / ${got_docx}) - Hợp lệ."
        fi
    done

    return "${bad}"
}

# MAIN EXECUTION
if [ "${MODE}" = "check" ]; then
    verify_status && log "Kết quả: Toàn bộ hệ thống bình thường!" || warn "Kết quả: Cần chạy fix để khắc phục lỗi!"
    exit $?
fi

fix_system
fix_users
verify_status
log "Hoàn tất! Người dùng có thể kéo thả upload file lên Google Drive ngay bây giờ."
