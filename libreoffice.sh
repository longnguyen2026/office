#!/usr/bin/env bash
#
# LibreOffice Clean Install v2.0
# longnguyen2026
# Kubuntu / Linux Mint / Ubuntu
# Official TDF DEB installer
#

set -Eeuo pipefail

VERSION="2.0"
WORK="$(mktemp -d -t libreoffice-v2-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[CANH BAO]${NC} $*"; }
fail() {
    echo -e "${RED}[LOI]${NC} $*" >&2
    exit 1
}

echo "========================================"
echo "     LIBREOFFICE CLEAN INSTALL v$VERSION"
echo "========================================"

# 1. Check OS
source /etc/os-release

case "${ID:-}" in
    ubuntu|linuxmint) ;;
    *)
        [[ " ${ID_LIKE:-} " == *" ubuntu "* ]] ||
            fail "Chi ho tro Ubuntu, Kubuntu va Linux Mint."
        ;;
esac

ARCH="$(dpkg --print-architecture)"
[[ "$ARCH" == "amd64" ]] || fail "Chi ho tro amd64."

for cmd in curl python3 dpkg-query dpkg-deb apt-get tar; do
    command -v "$cmd" >/dev/null ||
        fail "Thieu lenh: $cmd"
done

info "He dieu hanh: $PRETTY_NAME"
info "Kien truc: $ARCH"

# 2. Check old packages
echo
echo "===== LIBREOFFICE HIEN TAI ====="

if command -v libreoffice >/dev/null 2>&1; then
    libreoffice --version || true
else
    warn "Chua tim thay lenh libreoffice."
fi

mapfile -t OLD_PACKAGES < <(
    dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package}\n' 2>/dev/null |
    awk '$1 ~ /^ii/ {
        sub(/:.*/, "", $2)
        if ($2 ~ /^libreoffice/) print $2
    }' | sort -u
)

if ((${#OLD_PACKAGES[@]})); then
    printf '%s\n' "${OLD_PACKAGES[@]}"
else
    echo "Khong co goi LibreOffice cu."
fi

# 3. Download official download page
info "Dang tim phien ban Stable chinh thuc..."

PAGE="https://www.libreoffice.org/download/download-libreoffice/?type=deb-x86_64"

curl -fLsS --retry 3 "$PAGE" -o "$WORK/page.html" ||
    fail "Khong truy cap duoc trang tai LibreOffice."

# Extract exact official download URL
URL="$(
python3 - "$WORK/page.html" <<'PY'
import re
import sys
from html import unescape

html = open(sys.argv[1], encoding="utf-8", errors="ignore").read()
html = unescape(html)

patterns = [
    r'https?://download\.documentfoundation\.org/libreoffice/stable/[^"\'<>\s]+/LibreOffice_[^"\'<>\s]+_Linux_x86-64_deb\.tar\.gz',
    r'//download\.documentfoundation\.org/libreoffice/stable/[^"\'<>\s]+/LibreOffice_[^"\'<>\s]+_Linux_x86-64_deb\.tar\.gz',
]

for pattern in patterns:
    matches = re.findall(pattern, html, re.I)
    if matches:
        print(matches[0].replace("&amp;", "&").replace("//download.", "https://download."))
        break
PY
)" || fail "Khong tim thay URL bo cai chinh thuc."

[[ "$URL" == https://download.documentfoundation.org/libreoffice/stable/* ]] ||
    fail "URL tai ve khong hop le."

ARCHIVE="${URL##*/}"

info "Nguon tai: $URL"

# 4. Confirm before changing system
echo
echo "===== KE HOACH ====="
echo "1. Tai bo cai LibreOffice chinh thuc."
echo "2. Kiem tra cac goi DEB."
echo "3. Kiem tra cac goi co the bi go."
echo "4. Go cac goi LibreOffice cu neu co."
echo "5. Cai dat day du Writer, Calc, Impress..."
echo "6. Cai Desktop Integration."
echo
echo "KHONG chay apt autoremove."
echo "KHONG go Snap / Flatpak."
echo "KHONG xoa cau hinh nguoi dung."
echo

read -r -p "Tiep tuc? (y/N): " ANSWER
[[ "$ANSWER" =~ ^[Yy]$ ]] || exit 0

# 5. Download
info "Dang tai bo cai..."

curl -fL --retry 3 --progress-bar "$URL" \
    -o "$WORK/$ARCHIVE" ||
    fail "Tai bo cai that bai."

# 6. Extract
info "Dang giai nen..."

tar -xzf "$WORK/$ARCHIVE" -C "$WORK" ||
    fail "Khong giai nen duoc bo cai."

DEB_DIR="$(find "$WORK" -maxdepth 2 -type d -name DEBS -print -quit)"

[[ -n "$DEB_DIR" ]] || fail "Khong tim thay thu muc DEBS."

# 7. Collect all DEB packages
mapfile -d '' -t DEB_FILES < <(
    find "$DEB_DIR" -type f -name '*.deb' -print0
)

((${#DEB_FILES[@]} > 0)) ||
    fail "Khong tim thay goi DEB."

# 8. Verify required applications
HAS_WRITER=0
HAS_CALC=0
HAS_IMPRESS=0

for deb in "${DEB_FILES[@]}"; do
    PKG="$(dpkg-deb -f "$deb" Package 2>/dev/null || true)"

    [[ "$PKG" == *writer ]] && HAS_WRITER=1
    [[ "$PKG" == *calc ]] && HAS_CALC=1
    [[ "$PKG" == *impress ]] && HAS_IMPRESS=1
done

[[ "$HAS_WRITER" == 1 ]] || fail "Bo cai thieu Writer."
[[ "$HAS_CALC" == 1 ]] || fail "Bo cai thieu Calc."
[[ "$HAS_IMPRESS" == 1 ]] || fail "Bo cai thieu Impress."

info "Da xac minh Writer, Calc va Impress."

# 9. Install tools / update package lists
sudo apt-get update

# 10. Simulate old package removal
if ((${#OLD_PACKAGES[@]})); then
    info "Kiem tra viec go LibreOffice cu..."

    sudo apt-get -s purge "${OLD_PACKAGES[@]}" > "$WORK/purge.txt" ||
        fail "Khong the mo phong qua trinh go."

    while read -r ACTION PKG REST; do
        [[ "$ACTION" == "Remv" ]] || continue

        PKG="${PKG%%:*}"

        if [[ "$PKG" != libreoffice* ]]; then
            fail "APT muon go goi ngoai LibreOffice: $PKG. Da dung de bao ve he thong."
        fi
    done < "$WORK/purge.txt"

    echo
    echo "===== GOI DU KIEN GO ====="
    grep '^Remv ' "$WORK/purge.txt" || true

    read -r -p "Xac nhan go cac goi LibreOffice cu? (y/N): " PURGE_OK

    [[ "$PURGE_OK" =~ ^[Yy]$ ]] ||
        fail "Da huy thao tac go."

    sudo apt-get purge -y "${OLD_PACKAGES[@]}" ||
        fail "Go LibreOffice cu that bai."
fi

# 11. Simulate new installation
info "Kiem tra phu thuoc va cac goi se cai..."

sudo apt-get -s install "${DEB_FILES[@]}" > "$WORK/install.txt" ||
    fail "Khong the mo phong cai dat."

# Never allow removal of system packages
while read -r ACTION PKG REST; do
    [[ "$ACTION" == "Remv" ]] || continue

    PKG="${PKG%%:*}"

    if [[ "$PKG" != libreoffice* ]]; then
        fail "APT du kien go goi he thong: $PKG. Da dung de bao ve giao dien."
    fi
done < "$WORK/install.txt"

# 12. Install all official DEB files
info "Dang cai dat day du LibreOffice..."

sudo apt-get install -y "${DEB_FILES[@]}" ||
    fail "Cai dat that bai. Vui long kiem tra log APT."

# 13. Verify installed packages
echo
echo "===== KIEM TRA SAU CAI DAT ====="

for app in writer calc impress; do
    if ! dpkg-query -W -f='${db:Status-Abbrev}' \
        "libreoffice*-$app" 2>/dev/null |
        grep -q '^ii'; then
        fail "Chua xac minh duoc $app."
    fi
done

if ! command -v libreoffice >/dev/null 2>&1; then
    fail "Khong tim thay lenh libreoffice."
fi

libreoffice --version

# Check desktop launchers
LAUNCHERS=0

for f in /usr/share/applications/*libreoffice*.desktop; do
    [[ -f "$f" ]] && ((LAUNCHERS+=1))
done

if ((LAUNCHERS == 0)); then
    warn "Chua tim thay Desktop Launcher."
else
    info "Tim thay $LAUNCHERS Desktop Launcher."
fi

echo
echo "========================================"
echo "      CAI DAT THANH CONG"
echo "========================================"
echo "LibreOffice: $(libreoffice --version)"
echo "Writer: OK"
echo "Calc: OK"
echo "Impress: OK"
echo "Desktop Integration: da cai cac goi trong bo DEB"
echo
echo "Khong chay apt autoremove."
echo "Khong go Snap / Flatpak."
echo "========================================"
