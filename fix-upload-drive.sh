#!/usr/bin/env bash
# ==============================================================================
# Script: fix-upload-drive.sh
# Repo:   longnguyen2026/office
# Mô tả:  Khắc phục lỗi Google Drive không nhận diện file .xlsx, .docx, .pptx
#         do WPS Office ghi đè MIME type trên hệ thống Linux.
# ==============================================================================

set -euo pipefail

MODE="fix"
TARGET_USERS=""

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
    cat <<'EOF'
Cách sử dụng:
  curl -fsSL https://raw.githubusercontent.com/longnguyen2026/office/main/fix-upload-drive.sh | sudo bash
  hoặc:
  sudo bash fix-upload-drive.sh [TÙY CHỌN]

Tùy chọn:
  --check               Chỉ kiểm tra cấu hình hệ thống và user, không chỉnh sửa
  --users=u1,u2         Chỉ định danh sách user (mặc định: tự quét user UID >= 1000)
  -h, --help            Hiển thị trợ giúp này
EOF
    exit 0
}

for arg in "$@"; do
    case "${arg}" in
        --check) MODE="check" ;;
        --users=*) TARGET_USERS="${arg#--users=}" ;;
        -h|--help) usage ;;
        *) warn "Tham số không xác định: ${arg}" ;;
    esac
done

[ "$(id -u)" -eq 0 ] || die "Vui lòng chạy script với quyền sudo/root."

get_user_list() {
    if [ -n "${TARGET_USERS}" ]; then
        IFS=',' read -r -a USERS <<< "${TARGET_USERS}"
        echo "${USERS[@]}"
    else
        awk -F: '$3 >= 1000 && $3 < 60000 && $6 ~ /^\/home/ {print $1}' /etc/passwd
    fi
}

USER_LIST=($(get_user_list))

fix_system() {
    log ">>> [1/2] Dọn dẹp MIME độc quyền của WPS trên hệ thống..."
    rm -f /usr/share/mime/packages/wps-office-*.xml \
          /usr/share/mime/packages/wps-office*.xml 2>/dev/null || true
    rm -f /usr/share/mime/application/wps-office.*.xml 2>/dev/null || true

    mkdir -p /etc/skel/.config/Kingsoft
    cat > /etc/skel/.config/Kingsoft/Office.conf <<'EOF'
[6.0]
common\do_not_detect_file_association_while_startup=true
EOF
    chmod 0644 /etc/skel/.config/Kingsoft/Office.conf

    if command -v update-mime-database >/dev/null 2>&1; then
        update-mime-database /usr/share/mime >/dev/null 2>&1
        log "Đã cập nhật cơ sở dữ liệu MIME hệ thống (/usr/share/mime)."
    else
        die "Thiếu công cụ update-mime-database (gói shared-mime-info)."
    fi
}

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

fix_users() {
    log ">>> [2/2] Cấu hình chống tái tạo MIME cho từng người dùng..."
    local u home owner

    for u in "${USER_LIST[@]}"; do
        id "${u}" >/dev/null 2>&1 || continue
        home="$(getent passwd "${u}" | cut -d: -f6)"
        [ -d "${home}" ] || continue
        owner="$(stat -c '%U:%G' "${home}" 2>/dev/null || echo "${u}:${u}")"

        pkill -u "${u}" -f 'wps|et|wpp|prometheus|kingsoft' 2>/dev/null || true

        ensure_kingsoft_conf "${home}"

        rm -f "${home}/.local/share/mime/packages/Override.xml" 2>/dev/null || true
        rm -f "${home}/.local/share/mime/packages/"*wps* 2>/dev/null || true
        rm -f "${home}/.local/share/mime/application/wps-office.*.xml" 2>/dev/null || true

        if [ -d "${home}/.local/share/mime" ]; then
            if command -v update-mime-database >/dev/null 2>&1; then
                sudo -u "${u}" -H update-mime-database "${home}/.local/share/mime" >/dev/null 2>&1 || true
            fi
        fi

        chown -R "${owner}" "${home}/.config/Kingsoft" 2>/dev/null || true
        [ -d "${home}/.local/share/mime" ] && chown -R "${owner}" "${home}/.local/share/mime" 2>/dev/null || true

        log "Đã xử lý xong cho user: ${u}"
    done
}

verify_status() {
    log "=== KIỂM TRA ĐỊNH DẠNG MIME ==="
    local bad=0

    if grep -q 'wps-office' /usr/share/mime/globs2 2>/dev/null; then
        warn "Hệ thống: Vẫn còn ánh xạ WPS trong /usr/share/mime/globs2"
        bad=1
    else
        log "Hệ thống: /usr/share/mime/globs2 sạch, không còn wps-office.*"
    fi

    local u home
    for u in "${USER_LIST[@]}"; do
        id "${u}" >/dev/null 2>&1 || continue
        home="$(getent passwd "${u}" | cut -d: -f6)"
        [ -d "${home}" ] || continue

        local tmp_xlsx="${home}/.probe_test.xlsx"
        local tmp_docx="${home}/.probe_test.docx"
        touch "${tmp_xlsx}" "${tmp_docx}"
        chown "${u}:${u}" "${tmp_xlsx}" "${tmp_docx}" 2>/dev/null || true

        local got_xlsx got_docx
        got_xlsx="$(sudo -u "${u}" -H xdg-mime query filetype "${tmp_xlsx}" 2>/dev/null || true)"
        got_docx="$(sudo -u "${u}" -H xdg-mime query filetype "${tmp_docx}" 2>/dev/null || true)"
        rm -f "${tmp_xlsx}" "${tmp_docx}"

        if [[ "${got_xlsx}" == *"wps-office"* ]] || [[ "${got_docx}" == *"wps-office"* ]]; then
            warn "User ${u}: Vẫn bị gán MIME wps-office (${got_xlsx})"
            bad=1
        else
            log "User ${u}: xlsx -> ${got_xlsx:-OK} | docx -> ${got_docx:-OK}"
        fi
    done

    return "${bad}"
}

if [ "${MODE}" = "check" ]; then
    verify_status && log "Trạng thái: Tốt! Không phát hiện lỗi MIME." || warn "Trạng thái: Phát hiện lỗi MIME, cần chạy fix."
    exit $?
fi

fix_system
fix_users
verify_status
log "Hoàn tất! Người dùng có thể kéo thả upload file lên Google Drive bình thường."
