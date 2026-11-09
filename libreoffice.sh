#!/bin/bash
set -e

# Tự nâng quyền nếu chưa chạy qua sudo
if [ "$EUID" -ne 0 ]; then
  exec sudo bash "$0" "$@"
fi

echo "=================================================="
echo "    CÀI ĐẶT LIBREOFFICE MỚI NHẤT & DỌN DẸP HỆ THỐNG"
echo "=================================================="

# --- 1. GỠ BỎ TẬN GỐC SOFDMAKER FREEOFFICE 2024 ---
echo "--> Đang gỡ bỏ SoftMaker FreeOffice 2024..."
apt-get remove --purge -y softmaker-freeoffice-2024 softmaker-office-2024 2>/dev/null || true
rm -f /usr/share/applications/*freeoffice* /usr/share/applications/*textmaker* /usr/share/applications/*planmaker* /usr/share/applications/*presentations*
rm -f ~/.local/share/applications/*freeoffice* ~/.local/share/applications/*textmaker*
rm -rf /usr/share/freeoffice* /opt/freeoffice* ~/.softmaker
rm -f /etc/apt/sources.list.d/softmaker*

# --- 2. THÊM PPA VÀ CẬP NHẬT REPO ---
echo "--> Thêm PPA chính thức của LibreOffice..."
apt-get update
apt-get install -y software-properties-common
add-apt-repository -y ppa:libreoffice/ppa
apt-get update

# --- 3. CÀI ĐẶT ĐẦY ĐỦ CÁC GÓI ỨNG DỤNG CỐT LÕI ---
echo "--> Đang cài đặt LibreOffice (Writer, Calc, Impress, Draw)..."
# Cài đặt có khuyến nghị để kéo đủ libreoffice-core và file .desktop vào menu
apt-get install -y \
    libreoffice-writer \
    libreoffice-calc \
    libreoffice-impress \
    libreoffice-draw \
    libreoffice-gtk3 \
    libreoffice-kf5 \
    libreoffice-l10n-vi

# Gỡ bỏ riêng gói nlpsolver nếu bị kéo theo để không bị treo Java
apt-get remove --purge -y libreoffice-nlpsolver 2>/dev/null || true

# --- 4. LÀM MỚI MENU HỆ THỐNG ---
echo "--> Đang làm mới cơ sở dữ liệu menu..."
update-desktop-database /usr/share/applications/ 2>/dev/null || true
update-desktop-database ~/.local/share/applications/ 2>/dev/null || true

echo "=================================================="
echo "✔ HOÀN TẤT CÀI ĐẶT!"
echo -n "Đường dẫn nhị phân: "
which libreoffice
echo -n "Phiên bản hiện tại: "
libreoffice --version
echo "=================================================="
