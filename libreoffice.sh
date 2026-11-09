
#!/usr/bin/env bash
#
# LibreOffice Clean Install
# Kubuntu / Linux Mint / Ubuntu
# Install latest official stable DEB release
#

set -Eeuo pipefail

APP_NAME="LibreOffice Clean Install"
WORK_DIR="$(mktemp -d -t libreoffice-install-XXXXXX)"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[CANH BAO]${NC} $*"
}

error() {
    echo -e "${RED}[LOI]${NC} $*" >&2
}

echo "=========================================="
echo "       LIBREOFFICE CLEAN INSTALL"
echo "=========================================="

# 1. Check operating system
if [[ ! -f /etc/os-release ]]; then
    error "Khong xac dinh duoc he dieu hanh."
    exit 1
fi

source /etc/os-release

if [[ "$ID" != "ubuntu" && "$ID" != "linuxmint" ]]; then
    if [[ " ${ID_LIKE:-} " != *" ubuntu "* ]]; then
        error "Chi ho tro Kubuntu, Ubuntu va Linux Mint."
        exit 1
    fi
fi

# 2. Check architecture
ARCH="$(dpkg --print-architecture)"

if [[ "$ARCH" != "amd64" ]]; then
    error "Script nay chi ho tro CPU x86_64 (amd64)."
    exit 1
fi

# 3. Check commands
for cmd in curl python3 dpkg-query apt-get; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "Thieu lenh: $cmd"
        exit 1
    fi
done

info "He dieu hanh: $PRETTY_NAME"
info "Kien truc: $ARCH"

# 4. Show installed LibreOffice
echo
echo "===== LIBREOFFICE HIEN TAI ====="

if command -v libreoffice >/dev/null 2>&1; then
    libreoffice --version || true
else
    echo "Khong tim thay lenh libreoffice."
fi

echo
echo "===== CAC GOI APT DA CAI ====="

mapfile -t OLD_PACKAGES < <(
    dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' 2>/dev/null |
    awk '$1 ~ /^ii/ {
        sub(/:.*/, "", $2)
        if ($2 ~ /^libreoffice/) print $2
    }' |
    sort -u
)

if ((${#OLD_PACKAGES[@]})); then
    printf '%s\n' "${OLD_PACKAGES[@]}"
else
    echo "Khong co goi LibreOffice DEB cu."
fi

# 5. Detect Snap / Flatpak
echo
echo "===== CAC BAN CAI DAT KHAC ====="

if command -v snap >/dev/null 2>&1; then
    snap list libreoffice 2>/dev/null || true
fi

if command -v flatpak >/dev/null 2>&1; then
    flatpak list --app 2>/dev/null |
        grep -i libreoffice || true
fi

warn "Snap va Flatpak khong bi script tu dong go bo."

# 6. Find latest stable version from official website
echo
info "Dang kiem tra phien ban Stable moi nhat..."

DOWNLOAD_PAGE="https://www.libreoffice.org/download/download-libreoffice/?type=deb-x86_64"

HTML_FILE="$WORK_DIR/download.html"

if ! curl -fLsS --retry 3 "$DOWNLOAD_PAGE" -o "$HTML_FILE"; then
    error "Khong truy cap duoc trang LibreOffice."
    exit 1
fi

VERSION="$(
python3 - "$HTML_FILE" <<'PY'
import re
import sys

html = open(sys.argv[1], encoding="utf-8", errors="ignore").read()

versions = re.findall(
    r'LibreOffice_(\d+\.\d+\.\d+)_Linux_x86-64_deb\.tar\.gz',
    html
)

if not versions:
    sys.exit(1)

def key(v):
    return tuple(map(int, v.split(".")))

print(max(set(versions), key=key))
PY
)" || {
    error "Khong tim thay phien ban Stable trong trang tai ve."
    exit 1
}

info "Phien ban Stable moi nhat: $VERSION"

# 7. Ask user
echo
echo "=========================================="
echo " PHUONG AN CAI DAT"
echo "=========================================="
echo " - Go cac goi LibreOffice DEB cu."
echo " - Khong go Snap / Flatpak."
echo " - Khong xoa cau hinh nguoi dung."
echo " - Khong chay apt autoremove."
echo " - Tai LibreOffice $VERSION tu TDF."
echo " - Cai dat cac goi DEB chinh thuc."
echo "=========================================="

read -r -p "Ban co muon tiep tuc? (y/N): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    info "Da huy. Khong thay doi he thong."
    exit 0
fi

# 8. Close LibreOffice
if pgrep -x soffice >/dev/null 2>&1 ||
   pgrep -x soffice.bin >/dev/null 2>&1; then
    warn "Hay dong LibreOffice truoc khi tiep tuc."
    read -r -p "Nhan Enter sau khi da dong LibreOffice..."
fi

# 9. Remove old APT packages
if ((${#OLD_PACKAGES[@]})); then
    info "Dang go LibreOffice DEB cu..."

    sudo apt-get purge -y "${OLD_PACKAGES[@]}"
else
    info "Khong co goi DEB cu can go."
fi

# 10. Download official package
BASE_URL="https://download.documentfoundation.org/libreoffice/stable/$VERSION/deb/x86_64"

ARCHIVE="LibreOffice_${VERSION}_Linux_x86-64_deb.tar.gz"
URL="$BASE_URL/$ARCHIVE"

info "Dang tai LibreOffice $VERSION..."

if ! curl -fL --retry 3 --progress-bar "$URL" \
    -o "$WORK_DIR/$ARCHIVE"; then
    error "Tai bo cai that bai."
    exit 1
fi

# 11. Extract
info "Dang giai nen..."

tar -xzf "$WORK_DIR/$ARCHIVE" -C "$WORK_DIR"

DEB_DIR="$WORK_DIR/LibreOffice_${VERSION}_Linux_x86-64_deb/DEBS"

if [[ ! -d "$DEB_DIR" ]]; then
    error "Khong tim thay thu muc DEBS."
    exit 1
fi

# 12. Install
info "Dang cai dat LibreOffice..."

sudo apt-get update

sudo apt-get install -y "$DEB_DIR"/*.deb

# 13. Verify
echo
echo "=========================================="
echo " KIEM TRA SAU CAI DAT"
echo "=========================================="

if command -v libreoffice >/dev/null 2>&1; then
    libreoffice --version
    info "CAI DAT THANH CONG!"
else
    error "Khong tim thay lenh libreoffice sau cai dat."
    exit 1
fi

echo
echo "=========================================="
echo " HOAN TAT"
echo "=========================================="
echo "LibreOffice: $VERSION"
echo "He dieu hanh: $PRETTY_NAME"
echo
echo "Khong chay apt autoremove."
echo "Khong xoa ho so nguoi dung."
echo "=========================================="
