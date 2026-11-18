// Đọc số thành chữ tiếng Việt
var DOCSO_CONFIG = { donVi: " đồng", vietHoaChuDau: true };

var CS = ["không","một","hai","ba","bốn","năm","sáu","bảy","tám","chín"];

function docBaSo(n, full) {
  var tram = Math.floor(n / 100), chuc = Math.floor(n / 10) % 10, dv = n % 10, s = [];
  if (tram > 0 || full) { s.push(CS[tram], "trăm"); }
  if (chuc > 1) {
    s.push(CS[chuc], "mươi");
    if (dv === 1) s.push("mốt");
    else if (dv === 5) s.push("lăm");
    else if (dv > 0) s.push(CS[dv]);
  } else if (chuc === 1) {
    s.push("mười");
    if (dv === 5) s.push("lăm");
    else if (dv > 0) s.push(CS[dv]);
  } else if (dv > 0) {
    if (tram > 0 || full) s.push("lẻ");
    s.push(CS[dv]);
  }
  return s.join(" ");
}

function tenDonVi(i) {
  if (i === 0) return "";
  var base = ["tỷ", "nghìn", "triệu"];
  var u = base[i % 3];
  return (i >= 3 && i % 3 !== 0) ? u + " tỷ" : u;
}

function docSoNguyen(str) {
  str = str.replace(/^0+(?=\d)/, "");
  if (str === "0") return "không";
  var groups = [];
  for (var e = str.length; e > 0; e -= 3) groups.unshift(parseInt(str.substring(Math.max(0, e - 3), e), 10));
  var out = [], started = false;
  for (var k = 0; k < groups.length; k++) {
    var g = groups[k], idx = groups.length - 1 - k;
    if (g === 0) continue;
    out.push(docBaSo(g, started));
    var u = tenDonVi(idx);
    if (u) out.push(u);
    started = true;
  }
  return out.join(" ");
}

function docSo(value, opts) {
  opts = opts || DOCSO_CONFIG;
  if (value === null || value === undefined || value === "") return "";
  var s = String(value).trim().replace(/,/g, ".");
  if (/e/i.test(s)) return "(số quá lớn/nhỏ)";
  var neg = false;
  if (s.charAt(0) === "-") { neg = true; s = s.substring(1); }
  if (!/^\d+(\.\d+)?$/.test(s)) return "(không phải số)";
  var parts = s.split(".");
  if (parts[0].length > 18) return "(số quá lớn)";
  var r = docSoNguyen(parts[0]);
  if (parts[1]) {
    var dec = parts[1].replace(/0+$/, "");
    if (dec) r += " phẩy " + dec.split("").map(function (d) { return CS[+d]; }).join(" ");
  }
  if (neg) r = "âm " + r;
  r += (opts.donVi || "");
  if (opts.vietHoaChuDau && r) r = r.charAt(0).toUpperCase() + r.substring(1);
  return r;
}

if (typeof module !== "undefined") module.exports = { docSo: docSo };
