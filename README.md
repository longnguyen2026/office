# Lệnh cài Libreoffice:
````bash
curl -sSL https://raw.githubusercontent.com/longnguyen2026/office/main/libreoffice.sh | bash
````
### Lệnh sau cài được
```bash
curl -sSL https://raw.githubusercontent.com/longnguyen2026/office/main/libreoffice.sh -o /tmp/libreoffice.sh
sudo bash /tmp/libreoffice.sh
```
# Fix lỗi upload file xlsx, doc lên google drive và mở được file bằng goolge sheet, google doc
## WPS Office MIME Fix for Google Drive on Linux

Sửa lỗi khi upload file `.xlsx`, `.docx`, `.pptx` lên Google Drive từ Linux bị biến thành file không rõ định dạng, không mở được trực tiếp bằng Google Docs / Google Sheets.

### Nguyên nhân
Khi cài đặt WPS Office trên Linux, phần mềm tự tạo MIME type độc quyền (`application/wps-office.*`). Khi kéo thả file lên trình duyệt (Chrome, Firefox), trình duyệt gửi MIME type này lên Google Drive thay vì định dạng chuẩn OpenXML (`application/vnd.openxmlformats-officedocument.*`).

### Cách chạy nhanh (One-liner)

```bash
curl -fsSL [https://raw.githubusercontent.com/](https://raw.githubusercontent.com/)longnguyen2026/office/main/fix-upload-drive.sh | sudo bash
````
