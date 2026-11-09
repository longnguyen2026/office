#!/bin/bash
set -e

# Tự nâng quyền nếu chưa chạy qua sudo
if [ "$EUID" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

echo "=== 1. Dang go bo cac phien ban LibreOffice cu ==="
apt-get remove --purge -y "libreoffice*" "libobasis*" || true
rm -f /usr/share/applications/libreoffice*
rm -f /usr/local/share/applications/libreoffice*
rm -f /usr/bin/libreoffice

# Go Flatpak neu co
if command -v flatpak &> /dev/null; then
  if flatpak list | grep -q "org.libreoffice.LibreOffice"; then
    echo "Phat hien ban Flatpak, dang go bo..."
    flatpak uninstall --delete-data -y org.libreoffice.LibreOffice || true
  fi
fi

echo "=== 2. Them PPA va cap nhat kho phan mem ==="
apt-get update
apt-get install -y software-properties-common
add-apt-repository -y ppa:libreoffice/ppa
apt-get update

echo "=== 3. Cai dat LibreOffice moi nhat ==="
apt-get install -y libreoffice libreoffice-gtk3 libreoffice-l10n-vi

echo "=== 4. Lam moi database menu ==="
update-desktop-database /usr/share/applications/ || true

echo "=== HOAN TAT! ==="
libreoffice --version
