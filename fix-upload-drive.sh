#!/usr/bin/env bash
# ==============================================================================
# Script: fix-upload-drive.sh
# Repo:   longnguyen2026/office
# Mô tả:  Khắc phục lỗi Google Drive nhận sai MIME WPS mà không làm sập Desktop.
# ==============================================================================

set -euo pipefail

MODE="fix"
TARGET_USERS=""

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
  --check               Chỉ kiểm tra cấu hình MIME hiện tại
  --users=u1,u2         Chỉ định danh sách user (mặc định: quét UID >= 1000)
  -h, --help            Hiển thị trợ giúp
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

[ "$(id -u)" -eq 0 ] || die "Script yêu cầu quyền root/sudo."

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
    log ">>> [1/2] Dọn dẹp MIME WPS & tạo Override chuẩn OpenXML..."

    # Xóa file định nghĩa XML nguồn của WPS
    rm -f /usr/share/mime/packages/*business*.xml \
          /usr/share/mime/packages/*custom-wps*.xml \
          /usr/share/mime/packages/*wps*.xml \
          /usr/share/mime/packages/*kingsoft*.xml \
          /usr/local/share/mime/packages/*wps*.xml \
          /usr/local/share/mime/packages/*kingsoft*.xml \
          /usr/share/mime/application/wps-office.*.xml \
          /usr/local/share/mime/application/wps-office.*.xml 2>/dev/null || true

    # Tạo override chuẩn với trọng số 100
    cat > /usr/share/mime/packages/00-override-openxml.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet">
    <comment>Microsoft Excel OpenXML Spreadsheet</comment>
    <glob pattern="*.xlsx" weight="100"/>
    <glob pattern="*.XLSX" weight="100"/>
  </mime-type>
  <mime-type type="application/vnd.openxmlformats-officedocument.wordprocessingml.document">
    <comment>Microsoft Word OpenXML Document</comment>
    <glob pattern="*.docx" weight="100"/>
    <glob pattern="*.DOCX" weight="100"/>
  </mime-type>
  <mime-type type="application/vnd.openxmlformats-officedocument.presentationml.presentation">
    <comment>Microsoft PowerPoint OpenXML Presentation</comment>
    <glob pattern="*.pptx" weight="100"/>
    <glob pattern="*.PPTX" weight="100"/>
  </mime-type>
</mime-info>
EOF

    # Dọn dẹp desktop shortcuts
    for dt in /usr/share/applications/wps-office-*.desktop; do
        [ -f "$dt" ] || continue
        sed -i 's/application\/wps-office\.[^;]*;//g' "$dt"
    done

    # Cập nhật database an toàn (không dùng rm đối với mime.cache)
    if command -v update-mime-database >/dev/null 2>&1; then
        update-mime-database /usr/share/mime >/dev/null 2>&1
        [ -d /usr/local/share/mime ] && update-mime-database /usr/local/share/mime >/dev/null 2>&1 || true
    fi
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database /usr/share/applications 2>/dev/null || true

    # Cấu hình template user mới
    mkdir -p /etc/skel/.config/Kingsoft
    cat > /etc/skel/.config/Kingsoft/Office.conf <<'EOF'
[6.0]
common\do_not_detect_file_association_while_startup=true
EOF
    chmod 0644 /etc/skel/.config/Kingsoft/Office.conf
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
    log ">>> [2/2] Cấu hình chống tái tạo MIME cho các user..."
    local u home owner

    for u in "${USER_LIST[@]}"; do
        id "${u}" >/dev/null 2>&1 || continue
        home="$(getent passwd "${u}" | cut -d: -f6)"
        [ -d "${home}" ] || continue
        owner="$(stat -c '%U:%G' "${home}" 2>/dev/null || echo "${u}:${u}")"

        ensure_kingsoft_conf "${home}"

        # Xóa file override rác của WPS trong home user
        rm -rf "${home}/.local/share/mime/packages/"*wps* \
               "${home}/.local/share/mime/packages/Override.xml" 2>/dev/null || true

        chown -R "${owner}" "${home}/.config/Kingsoft" 2>/dev/null || true
        log "Đã xử lý: ${u}"
    done
}

verify_status() {
    log "=== BẮT ĐẦU KIỂM TRA (VERIFY) ==="
    local bad=0

    if grep -q 'wps-office' /usr/share/mime/globs2 2>/dev/null; then
        warn "Hệ thống: Vẫn còn MIME WPS trong /usr/share/mime/globs2!"
        bad=1
    else
        log "Hệ thống: /usr/share/mime/globs2 sạch."
    fi

    local u home
    for u in "${USER_LIST[@]}"; do
        id "${u}" >/dev/null 2>&1 || continue
        home="$(getent passwd "${u}" | cut -d: -f6)"
        [ -d "${home}" ] || continue

        local tmp_xlsx="${home}/.probe.xlsx"
        local tmp_docx="${home}/.probe.docx"
        echo "PK" > "${tmp_xlsx}"
        echo "PK" > "${tmp_docx}"
        chown "${u}:${u}" "${tmp_xlsx}" "${tmp_docx}" 2>/dev/null || true

        local got_xlsx got_docx
        got_xlsx="$(sudo -u "${u}" -H xdg-mime query filetype "${tmp_xlsx}" 2>/dev/null || true)"
        got_docx="$(sudo -u "${u}" -H xdg-mime query filetype "${tmp_docx}" 2>/dev/null || true)"
        rm -f "${tmp_xlsx}" "${tmp_docx}"

        if [[ "${got_xlsx}" == *"wps-office"* ]] || [[ "${got_docx}" == *"wps-office"* ]]; then
            warn "User ${u}: Vẫn dính MIME WPS (${got_xlsx})"
            bad=1
        else
            log "User ${u}: xlsx -> ${got_xlsx:-OK} | docx -> ${got_docx:-OK}"
        fi
    done

    return "${bad}"
}

if [ "${MODE}" = "check" ]; then
    verify_status && log "Hệ thống chuẩn!" || warn "Cần chạy fix!"
    exit $?
fi

fix_system
fix_users
verify_status
log "Hoàn tất! Đã chuẩn hóa MIME an toàn mà không làm gián đoạn phiên làm việc."
