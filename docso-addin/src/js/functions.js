// Hàm tự định nghĩa dùng trong công thức (WPS 12.1.0.20540 trở lên):
//   =VN.DOCSO(A1)      -> "Một nghìn không trăm lẻ một"
//   =VN.DOCSOTIEN(A1)  -> "Một nghìn không trăm lẻ một đồng"
// Dùng docSo() trong docso.js, đăng ký bằng wps.AddCustomFunction nên không cần manifest.xml/functions.json.

var DOCSO_NAMESPACE = "VN";

function DOCSO(so) {
  return docSo(so, { donVi: "", vietHoaChuDau: true });
}

function DOCSOTIEN(so) {
  return docSo(so, { donVi: " đồng", vietHoaChuDau: true });
}

function dangKyHam() {
  if (typeof wps === "undefined" || wps.AddCustomFunction === undefined) return false; // WPS cũ
  wps.AddCustomFunction(DOCSO_NAMESPACE, "DOCSO", DOCSO, {
    parameters: [{ name: "so", description: "Số cần đọc", type: "number" }],
    description: "Đọc số thành chữ tiếng Việt (không kèm đơn vị)",
    result: { type: "string" }
  });
  wps.AddCustomFunction(DOCSO_NAMESPACE, "DOCSOTIEN", DOCSOTIEN, {
    parameters: [{ name: "so", description: "Số tiền cần đọc", type: "number" }],
    description: "Đọc số thành chữ tiếng Việt, kèm chữ \"đồng\"",
    result: { type: "string" }
  });
  return true;
}

try { dangKyHam(); } catch (e) { /* không để lỗi đăng ký làm hỏng add-in */ }
