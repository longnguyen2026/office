#!/bin/bash
# Cài add-in "Đọc số" vào WPS Spreadsheets (Linux). Chạy: bash install.sh
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/src"
NAME=docso
VER=1.0.0

PUB=$(find "$HOME/.local/share" "$HOME/.config" -path "*jsaddons/publish.xml" 2>/dev/null | head -n1)
if [ -n "$PUB" ]; then
  BASE=$(dirname "$PUB")
else
  BASE="$HOME/.local/share/Kingsoft/wps/jsaddons"
  mkdir -p "$BASE"
fi
echo "Thư mục add-in WPS: $BASE"

DEST="$BASE/${NAME}_${VER}"
rm -rf "$DEST"
mkdir -p "$DEST"
cp -r "$SRC/." "$DEST/"

python3 - "$BASE" "$NAME" "$VER" <<'PY'
import sys, os, shutil
import xml.etree.ElementTree as ET
base, name, ver = sys.argv[1:4]
p = os.path.join(base, "publish.xml")
if os.path.exists(p):
    shutil.copy(p, p + ".bak")
    root = ET.parse(p).getroot()
else:
    root = ET.Element("jsplugins")
for e in list(root):
    if e.get("name") == name:
        root.remove(e)
ET.SubElement(root, "jsplugin", {
    "name": name, "type": "et", "url": f"{name}_{ver}", "version": ver,
    "enable": "enable_dev", "install": "null", "customDomain": ""})
ET.indent(root)
ET.ElementTree(root).write(p, encoding="UTF-8", xml_declaration=True)
PY

echo "Xong. Tắt hẳn WPS (pkill -f wps) rồi mở lại WPS Spreadsheets."
