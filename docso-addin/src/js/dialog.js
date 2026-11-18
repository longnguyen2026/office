// Logic của hộp thoại chọn ô đích (dialog.html)

function getApp() {
  try { if (window.Application) return window.Application; } catch (e) {}
  try { return wps.EtApplication(); } catch (e2) {}
  return null;
}

function colToNum(s) {
  var n = 0;
  for (var i = 0; i < s.length; i++) n = n * 26 + (s.charCodeAt(i) - 64);
  return n;
}
function numToCol(n) {
  var s = "";
  while (n > 0) { var m = (n - 1) % 26; s = String.fromCharCode(65 + m) + s; n = Math.floor((n - 1) / 26); }
  return s;
}

// "B1", "$B$1", "Sheet2!B1", "'Sheet 2'!B1:B5" -> {sheet,row,col}
function parseDiaChi(str) {
  str = String(str || "").trim().replace(/\$/g, "");
  var sheet = null, i = str.lastIndexOf("!");
  if (i >= 0) { sheet = str.substring(0, i).replace(/^'|'$/g, ""); str = str.substring(i + 1); }
  var m = /^([A-Za-z]{1,3})(\d{1,7})$/.exec(str.split(":")[0]);
  if (!m) return null;
  return { sheet: sheet, row: +m[2], col: colToNum(m[1].toUpperCase()) };
}

function docThamSo(search) {
  var q = {};
  String(search || "").replace(/^\?/, "").split("&").forEach(function (p) {
    if (!p) return;
    var kv = p.split("=");
    q[kv[0]] = decodeURIComponent(kv[1] || "");
  });
  return q;
}

function layWs(app, name) {
  if (!name) return app.ActiveSheet;
  try { return app.Sheets.Item(name); } catch (e) {}
  try { return app.Worksheets.Item(name); } catch (e2) {}
  return app.ActiveSheet;
}

function docNguon(app, q) {
  var ws = layWs(app, q.ws), out = [];
  for (var i = 0; i < +q.rows; i++)
    for (var j = 0; j < +q.cols; j++)
      out.push(ws.Cells.Item(+q.r + i, +q.c + j).Value2);
  return out;
}

function conDuLieu(v) { return v !== undefined && v !== null && v !== ""; }

// Trả về {loi} | {canXacNhan:n} | {ok, tu, den}
function dienTuDialog(app, q, diaChi, dong, daXacNhan) {
  var d = parseDiaChi(diaChi);
  if (!d) return { loi: "Địa chỉ ô không hợp lệ. Ví dụ: B1" };
  var values = docNguon(app, q), n = values.length;
  var tenWs = d.sheet || q.ws;

  // chặn ghi đè lên chính ô nguồn
  if (tenWs === q.ws && d.col >= +q.c && d.col < +q.c + +q.cols &&
      d.row <= +q.r + +q.rows - 1 && d.row + n - 1 >= +q.r) {
    return { loi: "Ô đích trùng với ô nguồn, sẽ làm mất số gốc. Hãy chọn ô đích khác." };
  }

  var ws = layWs(app, tenWs);
  if (!daXacNhan) {
    var co = 0;
    for (var k = 0; k < n; k++) if (conDuLieu(ws.Cells.Item(d.row + k, d.col).Value2)) co++;
    if (co > 0) return { canXacNhan: co };
  }
  var cfg = { donVi: dong ? " đồng" : "", vietHoaChuDau: true };
  for (var t = 0; t < n; t++) ws.Cells.Item(d.row + t, d.col).Value2 = docSo(values[t], cfg);
  return { ok: n, tu: numToCol(d.col) + d.row, den: numToCol(d.col) + (d.row + n - 1) };
}

function khoiTao() {
  var $ = function (id) { return document.getElementById(id); };
  var app = getApp(), q = docThamSo(location.search), ghiDe = false;
  var hien = function (cls, txt) { $("kq").className = cls; $("kq").textContent = txt; };

  var nguonText = numToCol(+q.c) + q.r;
  if (+q.rows * +q.cols > 1)
    nguonText += ":" + numToCol(+q.c + +q.cols - 1) + (+q.r + +q.rows - 1);
  $("nguon").textContent = nguonText;
  $("dich").value = numToCol(+q.c + +q.cols) + q.r; // mặc định: cột liền bên phải nguồn
  $("dich").oninput = function () { ghiDe = false; $("kq").textContent = ""; };

  if (!app) { hien("loi", "Không truy cập được WPS (Application) từ hộp thoại này."); return; }

  $("btnLay").onclick = function () {
    try {
      var sel = app.Selection, ten = app.ActiveSheet.Name;
      var s = numToCol(sel.Column) + sel.Row;
      $("dich").value = (ten !== q.ws) ? "'" + ten + "'!" + s : s;
      ghiDe = false;
      hien("ok", "Đã lấy ô đang chọn: " + s);
    } catch (e) { hien("loi", "Lỗi: " + e.message); }
  };

  $("btnDien").onclick = function () {
    try {
      var r = dienTuDialog(app, q, $("dich").value, $("dong").checked, ghiDe);
      if (r.loi) return hien("loi", r.loi);
      if (r.canXacNhan) {
        ghiDe = true;
        return hien("canh", "Có " + r.canXacNhan + " ô đích đã có dữ liệu. Bấm \"Điền\" lần nữa để ghi đè.");
      }
      ghiDe = false;
      hien("ok", "Đã điền " + r.ok + " ô, từ " + r.tu + " đến " + r.den + ".");
    } catch (e) { hien("loi", "Lỗi: " + e.message); }
  };

  $("btnDong").onclick = function () { try { window.close(); } catch (e) {} };
}

if (typeof window !== "undefined" && typeof document !== "undefined") {
  window.addEventListener("load", khoiTao);
}
if (typeof module !== "undefined") {
  module.exports = { parseDiaChi: parseDiaChi, numToCol: numToCol, docThamSo: docThamSo, dienTuDialog: dienTuDialog };
}
