#!/bin/bash
set -e

# Tự động nâng quyền nếu chưa chạy qua sudo
if [ "$EUID" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

echo "=================================================="
echo "    KIỂM TRA VÀ CẬP NHẬT LIBREOFFICE MỚI NHẤT     "
echo "=================================================="

# --- BƯỚC 1: KIỂM TRA BẢN HIỆN CÓ TRÊN MÁY ---
FOUND_OLD=0

echo "--> Đang kiểm tra LibreOffice trên hệ thống..."

if command -v libreoffice &> /dev/null; then
  CURRENT_VER=$(libreoffice --version 2>/dev/null || echo "Không xác định")
  echo "✔ Phát hiện LibreOffice APT/hệ thống: $CURRENT_VER"
  FOUND_OLD=1
fi

if command -v flatpak &> /dev/null && flatpak list | grep -q "org.libreoffice.LibreOffice"; then
  echo "✔ Phát hiện LibreOffice phiên bản Flatpak."
  FOUND_OLD=1
fi

if dpkg -l | grep -qE 'libobasis|libreoffice'; then
  FOUND_OLD=1
fi

# --- BƯỚC 2: GỠ BỎ TOÀN BỘ BẢN CŨ NẾU CÓ ---
if [ $FOUND_OLD -eq 1 ]; then
  echo "--> Đang tiến hành gỡ bỏ sạch sẽ các bản cũ..."
  
  # Gỡ các gói APT/DEB liên quan (không dùng autoremove -y để đảm bảo an toàn hệ thống)
  apt-get remove --purge -y "libreoffice*" "libobasis*" || true
  
  # Gỡ Flatpak nếu có
  if command -v flatpak &> /dev/null && flatpak list | grep -q "org.libreoffice.LibreOffice"; then
    flatpak uninstall --delete-data -y org.libreoffice.LibreOffice || true
  fi

  # Dọn dẹp shortcut menu và binary mồ côi
  rm -f /usr/share/applications/libreoffice*
  rm -f /usr/local/share/applications/libreoffice*
  rm -f ~/.local/share/applications/libreoffice*
  rm -f /usr/bin/libreoffice
  rm -rf /opt/libreoffice*

  echo "✔ Đã gỡ bỏ toàn bộ phiên bản cũ thành công."
else
  echo "✔ Không phát hiện bản LibreOffice cũ nào trên máy."
fi

# Đồng thời dọn dẹp SoftMaker FreeOffice (TextMaker) nếu có để tránh đụng độ
if dpkg -l | grep -qE 'softmaker|textmaker'; then
  echo "--> Đang gỡ bỏ SoftMaker FreeOffice tồn dư..."
  apt-get remove --purge -y "softmaker-freeoffice*" "textmaker*" "planmaker*" "presentations*" || true
  rm -rf /usr/share/freeoffice* /opt/freeoffice* ~/.softmaker || true
fi

# --- BƯỚC 3: THÊM PPA VÀ CÀI ĐẶT BẢN MỚI NHẤT ---
echo "--> Đang thêm PPA chính thức của LibreOffice..."
apt-get update
apt-get install -y software-properties-common
add-apt-repository -y ppa:libreoffice/ppa
apt-get update

echo "--> Đang cài đặt LibreOffice mới nhất..."
apt-get install -y libreoffice libreoffice-gtk3 libreoffice-l10n-vi

# --- BƯỚC 4: LÀM MỚI MENU HỆ THỐNG VÀ XÁC NHẬN ---
update-desktop-database /usr/share/applications/ || true

echo "=================================================="
echo "✔ HOÀN TẤT CÀI ĐẶT LIBREOFFICE!"
echo -n "Phiên bản hiện tại: "
libreoffice --version
echo "=================================================="
