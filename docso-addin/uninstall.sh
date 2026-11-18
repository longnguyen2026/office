#!/bin/bash
# Gỡ add-in "Đọc số". Chạy: bash uninstall.sh
set -e
NAME=docso
PUB=$(find "$HOME/.local/share" "$HOME/.config" -path "*jsaddons/publish.xml" 2>/dev/null | head -n1)
[ -n "$PUB" ] || { echo "Không tìm thấy publish.xml, không có gì để gỡ."; exit 0; }
BASE=$(dirname "$PUB")
rm -rf "$BASE/${NAME}_"*
python3 - "$PUB" "$NAME" <<'PY'
import sys
import xml.etree.ElementTree as ET
p, name = sys.argv[1:3]
tree = ET.parse(p); root = tree.getroot()
for e in list(root):
    if e.get("name") == name:
        root.remove(e)
ET.indent(root)
tree.write(p, encoding="UTF-8", xml_declaration=True)
PY
echo "Đã gỡ. Tắt hẳn WPS (pkill -f wps) rồi mở lại."
