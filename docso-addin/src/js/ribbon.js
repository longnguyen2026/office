// Ribbon + hành động cho WPS Spreadsheets (ET)
// Nút "Đọc số...": mở hộp thoại để chọn ô đích và điền chữ.
// Nhóm "Thủ công": 1. Lấy ô nguồn -> bấm ô đích -> 2. Điền (dự phòng).

var DOCSO_NGUON = null;

function OnAddinLoad(ribbonUI) {
  if (typeof wps.ribbonUI !== "object") wps.ribbonUI = ribbonUI;
  return true;
}

function getApp() {
  try { if (window.Application) return window.Application; } catch (e) {}
  try { return wps.EtApplication(); } catch (e2) {}
  return null;
}

function GetUrlPath() {
  var e = decodeURI(document.location.toString());
  if (e.indexOf("/") !== -1) e = e.substring(0, e.lastIndexOf("/"));
  return e;
}

function layNguon(app) {
  var sel = app.Selection;
  return { ws: app.ActiveSheet, row: sel.Row, col: sel.Column,
           rows: sel.Rows.Count, cols: sel.Columns.Count };
}

function docGiaTri(nguon) {
  var out = [];
  for (var i = 0; i < nguon.rows; i++)
    for (var j = 0; j < nguon.cols; j++)
      out.push(nguon.ws.Cells.Item(nguon.row + i, nguon.col + j).Value2);
  return out;
}

function moHopThoai(app) {
  var n = layNguon(app);
  var url = GetUrlPath() + "/dialog.html?r=" + n.row + "&c=" + n.col +
            "&rows=" + n.rows + "&cols=" + n.cols +
            "&ws=" + encodeURIComponent(n.ws.Name);
  var dpr = window.devicePixelRatio || 1;
  var w = 480 * dpr, h = 340 * dpr;
  if (typeof app.ShowDialog === "function") app.ShowDialog(url, "Đọc số thành chữ", w, h, false);
  else wps.ShowDialog(url, "Đọc số thành chữ", w, h, false);
}

function OnAction(control) {
  var id = control.Id;
  try {
    var app = getApp();
    if (id === "btnDocSo") {
      try { moHopThoai(app); }
      catch (e) {
        alert("Không mở được hộp thoại (" + e.message + ").\n" +
              "Hãy dùng nhóm \"Thủ công\": 1. Lấy ô nguồn -> bấm ô đích -> 2. Điền.");
      }
      return true;
    }
    if (id === "btnLayNguon") {
      DOCSO_NGUON = layNguon(app);
      alert("Đã lấy " + (DOCSO_NGUON.rows * DOCSO_NGUON.cols) +
            " ô nguồn. Bây giờ bấm vào ô muốn điền chữ, rồi bấm nút \"2. Điền\".");
      return true;
    }
    // btnDienDong / btnDienThuong
    if (!DOCSO_NGUON) {
      alert("Chưa có ô nguồn. Hãy bôi đen các ô số rồi bấm \"1. Lấy ô nguồn\" trước.");
      return true;
    }
    var cfg = { donVi: id === "btnDienThuong" ? "" : " đồng", vietHoaChuDau: true };
    var values = docGiaTri(DOCSO_NGUON), dest = app.Selection;
    var ws = app.ActiveSheet;
    for (var k = 0; k < values.length; k++)
      ws.Cells.Item(dest.Row + k, dest.Column).Value2 = docSo(values[k], cfg);
    alert("Đã điền " + values.length + " ô, bắt đầu từ dòng " + dest.Row + ", cột " + dest.Column + ".");
  } catch (e) {
    alert("Lỗi: " + e.message);
  }
  return true;
}
