#!/bin/bash
set -e

# Tự động nâng quyền nếu chưa chạy qua sudo
if [ "$EUID" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

echo "=================================================="
echo "    CÀI ĐẶT LIBREOFFICE MỚI NHẤT & DỌN DẸP HỆ THỐNG"
echo "=================================================="

# --- 1. GỠ BỎ TẬN GỐC SOFDMAKER FREEOFFICE 2024 (NẾU CÓ) ---
echo "--> Đang kiểm tra và gỡ bỏ SoftMaker FreeOffice 2024..."
apt-get remove --purge -y softmaker-freeoffice-2024 softmaker-office-2024 2>/dev/null || true
rm -f /usr/share/applications/*freeoffice* /usr/share/applications/*textmaker* /usr/share/applications/*planmaker* /usr/share/applications/*presentations*
rm -f ~/.local/share/applications/*freeoffice* ~/.local/share/applications/*textmaker*
rm -rf /usr/share/freeoffice* /opt/freeoffice* ~/.softmaker
rm -f /etc/apt/sources.list.d/softmaker*

# --- 2. GỠ BỎ SẠCH SẼ CÁC BẢN LIBREOFFICE CŨ ---
echo "--> Đang gỡ bỏ các phiên bản LibreOffice cũ..."

# Chỉ gỡ các gói đang thực sự cài đặt (tránh in lỗi Unable to locate package)
PKGS_TO_REMOVE=$(dpkg-query -W -f='${Package}\n' 'libreoffice*' 'libobasis*' 2>/dev/null || true)
if [ -n "$PKGS_TO_REMOVE" ]; then
  echo "$PKGS_TO_REMOVE" | xargs apt-get remove --purge -y 2>/dev/null || true
fi

# Gỡ Flatpak nếu có
if command -v flatpak &> /dev/null && flatpak list | grep -q "org.libreoffice.LibreOffice"; then
  flatpak uninstall --delete-data -y org.libreoffice.LibreOffice || true
fi

# Dọn dẹp shortcut mồ côi và thư mục cài tay
rm -f /usr/share/applications/libreoffice*
rm -f /usr/local/share/applications/libreoffice*
rm -f ~/.local/share/applications/libreoffice*
rm -f /usr/bin/libreoffice
rm -rf /opt/libreoffice*

# --- 3. THÊM PPA VÀ CÀI ĐẶT BẢN MỚI NHẤT (SIÊU NHANH) ---
echo "--> Thêm PPA chính thức của LibreOffice..."
apt-get update
apt-get install -y software-properties-common
add-apt-repository -y ppa:libreoffice/ppa
apt-get update

echo "--> Đang cài đặt các ứng dụng LibreOffice cốt lõi..."
# Thêm --no-install-recommends để KHÔNG cài Java, Firebird và NLPSolver (tránh bị treo/chậm)
apt-get install -y --no-install-recommends \
    libreoffice-writer \
    libreoffice-calc \
    libreoffice-impress \
    libreoffice-draw \
    libreoffice-gtk3 \
    libreoffice-kf5 \
    libreoffice-qt5 \
    libreoffice-l10n-vi

# --- 4. LÀM MỚI MENU HỆ THỐNG ---
echo "--> Đang làm mới cơ sở dữ liệu menu..."
update-desktop-database /usr/share/applications/ 2>/dev/null || true
update-desktop-database ~/.local/share/applications/ 2>/dev/null || true

echo "=================================================="
echo "✔ HOÀN TẤT CÀI ĐẶT!"
echo -n "Phiên bản hiện tại: "
libreoffice --version
echo "=================================================="
