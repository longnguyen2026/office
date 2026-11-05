#!/bin/bash
set -e

echo "=== 1. Dang kiem tra quyen root ==="
if [ "$EUID" -ne 0 ]; then
  echo "Loi: Vui long chay script voi sudo (sudo bash $0)"
  exit 1
fi

echo "=== 2. Dang go bo cac phien ban LibreOffice cu (APT/DEB) ==="
# Chi go dung cac goi lien quan den LibreOffice, khong dung autoremove -y de tranh mat DE
apt remove --purge -y "libreoffice*" "libobasis*" || true

# Don cac file .desktop mo coi va symlink cu
rm -f /usr/share/applications/libreoffice*
rm -f /usr/local/share/applications/libreoffice*
rm -f /usr/bin/libreoffice

# Go bo ban Flatpak neu co ton tai
if command -v flatpak &> /dev/null; then
  if flatpak list | grep -q "org.libreoffice.LibreOffice"; then
    echo "Phat hien ban Flatpak, dang go bo..."
    flatpak uninstall --delete-data -y org.libreoffice.LibreOffice || true
  fi
fi

echo "=== 3. Them PPA chinh thuc va cap nhat kho phan mem ==="
apt update
apt install -y software-properties-common
add-apt-repository -y ppa:libreoffice/ppa
apt update

echo "=== 4. Tien hanh cai dat LibreOffice moi nhat tu PPA ==="
apt install -y libreoffice libreoffice-gtk3 libreoffice-l10n-vi

echo "=== 5. Lam moi menu he thong ==="
update-desktop-database /usr/share/applications/ || true

echo "=== HOAN TAT! Phien ban hien tai: ==="
libreoffice --version
