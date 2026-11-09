#!/bin/bash
set -e

# Tu nang quyen neu chua chay qua sudo
if [ "$EUID" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

echo "=== 1. Go bo sach cac ban LibreOffice cu ==="
apt-get remove --purge -y "libreoffice*" "libobasis*" || true
rm -f /usr/share/applications/libreoffice*
rm -f /usr/local/share/applications/libreoffice*
rm -f /usr/bin/libreoffice

# Go bo SoftMaker FreeOffice neu ton tai de tranh nham lan
echo "=== 2. Kiem tra va go bo SoftMaker FreeOffice (TextMaker, PlanMaker) ==="
apt-get remove --purge -y "softmaker-freeoffice*" "textmaker*" "planmaker*" "presentations*" || true
rm -rf /usr/share/freeoffice* /opt/freeoffice* ~/.softmaker || true

# Go Flatpak neu co
if command -v flatpak &> /dev/null; then
  if flatpak list | grep -q "org.libreoffice.LibreOffice"; then
    echo "Phat hien ban Flatpak, dang go bo..."
    flatpak uninstall --delete-data -y org.libreoffice.LibreOffice || true
  fi
fi

echo "=== 3. Them PPA va cap nhat kho phan mem ==="
apt-get update
apt-get install -y software-properties-common
add-apt-repository -y ppa:libreoffice/ppa
apt-get update

echo "=== 4. Cai dat LibreOffice moi nhat ==="
apt-get install -y libreoffice libreoffice-gtk3 libreoffice-l10n-vi

echo "=== 5. Lam moi database menu he thong ==="
update-desktop-database /usr/share/applications/ || true

echo "=== HOAN TAT! Phien ban hien tai: ==="
libreoffice --version
