#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# 1. Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR] Vui lòng chạy script với quyền sudo: curl -fsSL <url> | sudo bash${NC}"
    exit 1
fi

# 2. Kiểm tra phiên bản WPS Office (Bắt buộc >= 12.x)
WPS_VER=$(dpkg-query -W -f='${Version}' wps-office 2>/dev/null || true)

if [ -z "$WPS_VER" ]; then
    echo -e "${RED}[ERROR] Máy chưa cài đặt WPS Office! Vui lòng cài WPS 12 trước khi chạy script này.${NC}"
    exit 1
fi

if [[ ! "$WPS_VER" =~ ^12\. ]]; then
    echo -e "${YELLOW}[WARN] Phiên bản WPS hiện tại là ($WPS_VER). Add-in Đổi số thành chữ chỉ hỗ trợ WPS 12 trở lên.${NC}"
    exit 1
fi

echo -e "${CYAN}[INFO] Phát hiện WPS Office phiên bản $WPS_VER hợp lệ. Đang tải và tích hợp Add-in Đổi số thành chữ...${NC}"

# 3. Đảm bảo có công cụ unzip để giải nén gói từ GitHub
if ! command -v unzip >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq unzip >/dev/null 2>&1
fi

ADDIN_TMP="/tmp/docso-addin-repo"
rm -rf "$ADDIN_TMP"

# 4. Tải mã nguồn từ GitHub và cài đặt cho toàn bộ user trong /home/*
if curl -fsSL "https://github.com/longnguyen2026/office/archive/refs/heads/main.zip" -o "/tmp/office-main.zip"; then
    unzip -q "/tmp/office-main.zip" -d "$ADDIN_TMP"
    rm -f "/tmp/office-main.zip"

    SRC_DIR="$ADDIN_TMP/office-main/docso-addin/src"
    if [ -d "$SRC_DIR" ]; then
        for USER_HOME in /home/*; do
            [ -d "$USER_HOME" ] || continue
            TARGET_USER=$(basename "$USER_HOME")
            id "$TARGET_USER" &>/dev/null || continue

            JSADDONS_DIR="$USER_HOME/.local/share/Kingsoft/wps/jsaddons"
            PLUGIN_DIR="$JSADDONS_DIR/docso-addin_1.0.0"

            mkdir -p "$PLUGIN_DIR"
            rm -rf "$PLUGIN_DIR"/*
            cp -rf "$SRC_DIR"/* "$PLUGIN_DIR/"

            # Tạo hoặc cập nhật publish.xml
            PUBLISH_XML="$JSADDONS_DIR/publish.xml"
            if [ ! -f "$PUBLISH_XML" ]; then
                cat << 'EOF' > "$PUBLISH_XML"
<?xml version="1.0" encoding="UTF-8"?>
<jsplugins>
  <jsplugin name="docso-addin" type="et" url="http://127.0.0.1:3888/" version="1.0.0" enable="enable" install="1"/>
</jsplugins>
EOF
            else
                if ! grep -q 'name="docso-addin"' "$PUBLISH_XML"; then
                    sed -i 's|</jsplugins>|  <jsplugin name="docso-addin" type="et" url="http://127.0.0.1:3888/" version="1.0.0" enable="enable" install="1"/>\n</jsplugins>|' "$PUBLISH_XML"
                fi
            fi

            # Kích hoạt tính năng JS Add-in trong Office.conf
            CONF_FILE="$USER_HOME/.config/Kingsoft/Office.conf"
            mkdir -p "$USER_HOME/.config/Kingsoft"
            if ! grep -q "wpsoffice\\\\Application%20Settings\\\\enablejsaddons" "$CONF_FILE" 2>/dev/null; then
                cat << 'EOF' >> "$CONF_FILE"

[6.0]
wpsoffice\Application%20Settings\enablejsaddons=true
EOF
            fi

            chown -R "$TARGET_USER:$TARGET_USER" "$USER_HOME/.local/share/Kingsoft" "$USER_HOME/.config/Kingsoft"
        done
        echo -e "${GREEN}[SUCCESS] Đã tích hợp Add-in Đổi số thành chữ vào WPS Spreadsheets!${NC}"
    else
        echo -e "${RED}[ERROR] Không tìm thấy thư mục docso-addin/src trên GitHub.${NC}"
        rm -rf "$ADDIN_TMP"
        exit 1
    fi
    rm -rf "$ADDIN_TMP"
else
    echo -e "${RED}[ERROR] Không thể tải mã nguồn Add-in từ GitHub.${NC}"
    exit 1
fi
