# ==============================================================================
# [BỔ SUNG] TỰ ĐỘNG CÀI ĐẶT ADD-IN ĐỔI SỐ THÀNH CHỮ (DOCSO) CHO WPS 12
# ==============================================================================
echo -e "${CYAN}[INFO] Đang tải và tích hợp Add-in Đổi số thành chữ vào WPS Office 12...${NC}"

ADDIN_TMP="/tmp/docso-addin-repo"
rm -rf "$ADDIN_TMP"

# Tải mã nguồn repo office (hoặc chỉ tải gói zip)
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

            # Tạo hoặc cập nhật file publish.xml để WPS 12 tự nạp Add-in khi mở
            PUBLISH_XML="$JSADDONS_DIR/publish.xml"
            if [ ! -f "$PUBLISH_XML" ]; then
                cat << 'EOF' > "$PUBLISH_XML"
<?xml version="1.0" encoding="UTF-8"?>
<jsplugins>
  <jsplugin name="docso-addin" type="et" url="http://127.0.0.1:3888/" version="1.0.0" enable="enable" install="1"/>
</jsplugins>
EOF
            else
                # Nếu đã có publish.xml nhưng chưa đăng ký docso-addin thì chèn thêm
                if ! grep -q 'name="docso-addin"' "$PUBLISH_XML"; then
                    sed -i 's|</jsplugins>|  <jsplugin name="docso-addin" type="et" url="http://127.0.0.1:3888/" version="1.0.0" enable="enable" install="1"/>\n</jsplugins>|' "$PUBLISH_XML"
                fi
            fi

            # Bật quyền cho phép chạy JS Add-in cục bộ trong Office.conf của WPS 12
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
        echo -e "${YELLOW}[WARN] Không tìm thấy thư mục docso-addin/src trên GitHub.${NC}"
    fi
    rm -rf "$ADDIN_TMP"
else
    echo -e "${YELLOW}[WARN] Không thể tải mã nguồn Add-in từ GitHub.${NC}"
fi
