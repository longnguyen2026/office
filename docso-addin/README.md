# Add-in "Đọc số" cho WPS Spreadsheets (Linux)

Đọc số thành chữ tiếng Việt, người dùng tự chọn ô để điền chữ.

## Cách dùng
1. Bôi đen các ô số (nguồn).
2. Tab **Đọc số** → **Đọc số...** → hộp thoại hiện ra.
3. Chọn ô đích: gõ địa chỉ (vd `B1`, `Sheet2!C5`) hoặc bấm vào ô trên bảng tính rồi bấm **Lấy ô đang chọn**.
4. Tích/bỏ tích **Thêm chữ "đồng"** → **Điền**.

Chữ điền xuống dưới từ ô đích, mỗi ô nguồn một dòng (nguồn nhiều cột thì đọc từng dòng, trái sang phải).
An toàn: không cho ghi đè lên ô nguồn; nếu ô đích đã có dữ liệu thì cảnh báo và chỉ ghi đè khi bấm **Điền** lần nữa.

**Dự phòng (nhóm "Thủ công")** nếu hộp thoại không mở được: bôi đen ô số → **1. Lấy ô nguồn** → bấm ô đích → **2. Điền**.

Ví dụ: `1500000` → "Một triệu năm trăm nghìn đồng". Hỗ trợ số âm, số thập phân ("phẩy"), tới hàng trăm triệu tỷ.

## Dùng như hàm trong công thức (cần WPS 12.1.0.20540 trở lên)
    =VN.DOCSO(A1)       ->  Một nghìn không trăm lẻ một
    =VN.DOCSOTIEN(A1)   ->  Một nghìn không trăm lẻ một đồng
Cũng tìm được ở nút fx → nhóm **User Defined** (Người dùng định nghĩa). Kết quả tự cập nhật khi đổi số.
Hàm chỉ hoạt động trên máy đã cài add-in; gửi file cho người khác thì nên dán giá trị (Paste Values) để tránh lỗi `#NAME?`.

## Cài đặt
    pkill -f wps
    bash install.sh
Mở lại WPS Spreadsheets. Gỡ: `bash uninstall.sh`.

## Cấu trúc
- `src/index.html`    trang nạp add-in
- `src/dialog.html`   hộp thoại chọn ô đích
- `src/js/dialog.js`  logic hộp thoại (đọc nguồn, kiểm tra, điền chữ)
- `src/js/functions.js` đăng ký hàm `VN.DOCSO`, `VN.DOCSOTIEN`
- `src/ribbon.xml`    khai báo tab và nút
- `src/js/ribbon.js`  xử lý khi bấm nút (đọc vùng chọn, ghi kết quả)
- `src/js/docso.js`   thuật toán đọc số (không phụ thuộc WPS, test được bằng Node)

## Tuỳ chỉnh
Đổi đơn vị "đồng" hoặc bỏ viết hoa chữ đầu: sửa `DOCSO_CONFIG` đầu file `src/js/docso.js`, rồi chạy lại `bash install.sh`.

## Test thuật toán
    node -e "console.log(require('./src/js/docso.js').docSo(1001,{donVi:''}))"

## Ghi chú
Cách đăng ký offline qua `publish.xml` dựa trên định dạng cộng đồng WPS, chưa kiểm chứng trên mọi phiên bản.
Nếu tab không hiện, kiểm tra `~/.local/share/Kingsoft/wps/jsaddons/publish.xml`.
