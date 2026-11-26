#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "❌ Vui lòng chạy script bằng quyền sudo (ví dụ: curl -sL <link> | sudo bash)"
  exit 1
fi

echo "⏳ [1/4] Đang kiểm tra và cài đặt các thư viện phụ thuộc..."
apt-get update -qq
apt-get install -y --no-install-recommends \
  python3 python3-cups cups cups-client cups-filters-core-drivers cups-filters policykit-1 >/dev/null

echo "📦 [2/4] Đang tạo mã nguồn và các tệp hệ thống..."
install -d -m 0755 /usr/lib/onlyoffice-printer-fix
install -d -m 0700 /var/lib/onlyoffice-printer-fix
install -d -m 0755 /etc/xdg/autostart
install -d -m 0755 /usr/share/applications
install -d -m 0755 /usr/lib/systemd/system

# 1. File chính: /usr/lib/onlyoffice-printer-fix/fix.py
cat << 'EOF' > /usr/lib/onlyoffice-printer-fix/fix.py
#!/usr/bin/python3
"""Repair missing PPDs for local IPP queues used by ONLYOFFICE (CUPS 2)."""
import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit
import uuid

import cups

STATE = Path('/var/lib/onlyoffice-printer-fix')
DRIVERLESS = '/usr/lib/cups/driver/driverless'
LPCONF = '/usr/sbin/lpadmin'


def local_connection():
    for socket in ('/run/cups/cups.sock', '/var/run/cups/cups.sock'):
        if Path(socket).exists():
            return cups.Connection(host=socket)
    raise RuntimeError('CUPS chưa chạy hoặc không có socket cục bộ.')


def ppd_bytes(conn, name):
    """None means confirmed missing, not a connection/permission failure."""
    try:
        filename = conn.getPPD(name)
    except cups.IPPError as exc:
        if exc.args[0] == cups.IPP_NOT_FOUND:
            return None
        raise
    if not filename:
        raise RuntimeError('CUPS không trả về tệp PPD.')
    try:
        return Path(filename).read_bytes()
    finally:
        Path(filename).unlink(missing_ok=True)


def safe_name(name):
    return bool(name and name not in ('.', '..') and
                not any(c in name for c in '/\\\x00\r\n'))


def queue_jobs(conn, name):
    jobs = conn.getJobs(which_jobs='not-completed',
                        requested_attributes=['job-printer-uri'])
    for job in jobs.values():
        uri = job.get('job-printer-uri')
        if not uri or unquote(urlsplit(uri).path.rsplit('/', 1)[-1]).lower() == name.lower():
            return True
    return False


def classify(conn, name, attrs):
    if not safe_name(name):
        return 'skip', 'tên queue không hợp lệ'
    if ppd_bytes(conn, name) is not None:
        return 'ok', 'đã có PPD; giữ nguyên'
    if attrs.get('printer-is-temporary', False):
        return 'skip', 'queue tạm; cần cài queue cố định'
    uri = attrs.get('device-uri', '')
    parsed = urlsplit(uri)
    if parsed.scheme not in ('ipp', 'ipps') or not parsed.hostname:
        return 'skip', 'thiếu PPD nhưng không dùng IPP/IPPS; cần driver phù hợp'
    if parsed.username or parsed.password:
        return 'skip', 'URI có thông tin đăng nhập; cần cấu hình thủ công'
    if queue_jobs(conn, name):
        return 'skip', 'còn lệnh in; sẽ thử lại khi hàng đợi trống'
    return 'candidate', 'thiếu PPD; có thể tạo cấu hình driverless'


def generate_ppd(uri, directory):
    path = Path(directory) / 'generated.ppd'
    with path.open('wb') as out:
        result = subprocess.run([DRIVERLESS, uri], stdout=out,
                                stderr=subprocess.DEVNULL, timeout=25, check=False)
    if result.returncode or not path.exists() or not 100 < path.stat().st_size < 4_000_000:
        raise RuntimeError('không tạo được PPD: kiểm tra kết nối và khả năng hỗ trợ IPP của máy in')
    result = subprocess.run(['/usr/bin/cupstestppd', '-v', str(path)],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            env={'LC_ALL': 'C', 'PATH': '/usr/sbin:/usr/bin:/sbin:/bin'},
                            text=True, encoding='utf-8', errors='replace',
                            timeout=10, check=False)
    if result.returncode:
        failures = [line.strip() for line in result.stdout.splitlines() if '**FAIL**' in line]
        cosmetic = re.compile(r'^\*\*FAIL\*\*\s+Default translation string for option '
                              r'\S+ choice \S+ contains 8-bit characters\.$')
        if result.returncode != 4 or not failures or not all(cosmetic.fullmatch(x) for x in failures):
            raise RuntimeError('PPD tạo ra không qua kiểm tra; giữ nguyên queue')
    cups.PPD(str(path))
    return path


def preserve_flags(conn, name, before):
    after = conn.getPrinterAttributes(name)
    shared = bool(before.get('printer-is-shared', False))
    if bool(after.get('printer-is-shared', False)) != shared:
        conn.setPrinterShared(name, shared)
    stopped = before.get('printer-state') == 5
    if (after.get('printer-state') == 5) != stopped:
        if stopped:
            conn.disablePrinter(name, reason=before.get('printer-state-message', ''))
        else:
            conn.enablePrinter(name)
    accepting = bool(before.get('printer-is-accepting-jobs', True))
    if bool(after.get('printer-is-accepting-jobs', True)) != accepting:
        if accepting:
            conn.acceptJobs(name)
        else:
            conn.rejectJobs(name)


def write_record(folder, record):
    temp = folder / 'record.json.tmp'
    temp.write_text(json.dumps(record, ensure_ascii=False, indent=2, default=str) + '\n')
    temp.replace(folder / 'record.json')


def raw_again(conn, name, attrs):
    socket = '/run/cups/cups.sock' if Path('/run/cups/cups.sock').exists() else '/var/run/cups/cups.sock'
    subprocess.run([LPCONF, '-h', socket, '-p', name, '-m', 'raw'],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   check=True, timeout=15)
    preserve_flags(conn, name, attrs)


def repair_one(conn, name, original, state=STATE, generator=generate_ppd):
    uri = original['device-uri']
    with tempfile.TemporaryDirectory(prefix='onlyoffice-printer-fix-') as temp:
        ppd = generator(uri, temp)
        before = conn.getPrinterAttributes(name)
        if before.get('device-uri') != uri or classify(conn, name, before)[0] != 'candidate':
            raise RuntimeError('queue đã thay đổi hoặc có lệnh in; chưa sửa, hãy chạy lại')
        state.mkdir(mode=0o700, parents=True, exist_ok=True)
        backup_id = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ-') + uuid.uuid4().hex[:8]
        folder = state / backup_id
        folder.mkdir(mode=0o700)
        record = {'version': 1, 'queue': name, 'before': before, 'status': 'prepared'}
        write_record(folder, record)
        try:
            conn.addPrinter(name, filename=str(ppd))
            preserve_flags(conn, name, before)
            installed = ppd_bytes(conn, name)
            if not installed:
                raise RuntimeError('CUPS chưa lưu PPD mới')
            record.update(status='repaired', ppd_sha256=hashlib.sha256(installed).hexdigest())
            write_record(folder, record)
        except Exception:
            try:
                raw_again(conn, name, before)
                record['status'] = 'rolled-back'
            except Exception:
                record['status'] = 'rollback-needed'
            write_record(folder, record)
            raise
    return backup_id


def restore(conn, backup_id):
    if not re.fullmatch(r'\d{8}T\d{6}Z-[0-9a-f]{8}', backup_id):
        raise RuntimeError('Mã bản sao lưu không hợp lệ.')
    folder = STATE / backup_id
    record = json.loads((folder / 'record.json').read_text())
    if record.get('status') != 'repaired':
        raise RuntimeError('Bản sao lưu này không ở trạng thái có thể khôi phục tự động.')
    name = record['queue']
    current = conn.getPrinterAttributes(name)
    if current.get('device-uri') != record['before']['device-uri'] or queue_jobs(conn, name):
        raise RuntimeError('Queue đã đổi địa chỉ hoặc đang có lệnh in; chưa khôi phục.')
    current_ppd = ppd_bytes(conn, name)
    if current_ppd is None or hashlib.sha256(current_ppd).hexdigest() != record['ppd_sha256']:
        raise RuntimeError('Driver đã được chỉnh sau khi sửa; chưa khôi phục để tránh ghi đè.')
    raw_again(conn, name, current)
    record['status'] = 'restored'
    write_record(folder, record)
    print('Đã khôi phục queue về trạng thái thiếu PPD ban đầu:', name)


def onlyoffice_running():
    uid = os.getuid()
    for item in Path('/proc').iterdir():
        if not item.name.isdigit():
            continue
        try:
            if item.stat().st_uid == uid and (item / 'comm').read_text().strip() == 'DesktopEditors':
                return True
        except (OSError, UnicodeError):
            continue
    return False


def refresh_user(conn, quiet=False):
    if os.geteuid() == 0:
        raise RuntimeError('Chạy --refresh-user bằng tài khoản người dùng, không dùng sudo.')
    if onlyoffice_running():
        if not quiet:
            print('ONLYOFFICE đang mở. Hãy lưu tài liệu, thoát hẳn rồi mở lại để nhận máy in.')
        return
    home = Path(pwd.getpwuid(os.getuid()).pw_dir)
    cache = home / '.local/share/onlyoffice/desktopeditors/printers.cache'
    conf = home / '.config/onlyoffice/DesktopEditors.conf'
    printers = conn.getPrinters()
    usable = []
    for name in sorted(printers):
        try:
            if ppd_bytes(conn, name):
                usable.append(name)
        except cups.IPPError:
            continue
    if not usable:
        if not quiet:
            print('Chưa có queue có PPD. Chạy chế độ sửa trước.')
        return
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup = home / '.local/state/onlyoffice-printer-fix' / stamp
    changed = False
    if cache.is_file():
        try:
            names = sorted(p['name'] for p in json.loads(cache.read_text())['printers'])
        except (ValueError, KeyError, TypeError):
            names = []
        if names != usable:
            backup.mkdir(parents=True, mode=0o700, exist_ok=True)
            shutil.copy2(cache, backup / 'printers.cache')
            cache.unlink()
            changed = True
    if conf.is_file():
        text = conf.read_text()
        match = re.search(r'^lastPrinterName=(.*)$', text, flags=re.M)
        enabled = [name for name in usable if printers[name].get('printer-state') != 5
                   and printers[name].get('printer-is-accepting-jobs', True)]
        if match and enabled and match.group(1) not in enabled:
            default = conn.getDefault()
            selected = default if default in enabled else enabled[0]
            updated = text[:match.start(1)] + selected + text[match.end(1):]
            backup.mkdir(parents=True, mode=0o700, exist_ok=True)
            shutil.copy2(conf, backup / conf.name)
            fd, filename = tempfile.mkstemp(prefix='.print-fix-', dir=str(conf.parent))
            try:
                with os.fdopen(fd, 'w') as stream:
                    stream.write(updated)
                os.chmod(filename, conf.stat().st_mode & 0o777)
                os.replace(filename, conf)
            finally:
                Path(filename).unlink(missing_ok=True)
            changed = True
    if changed or not quiet:
        print('Đã kiểm tra cấu hình in ONLYOFFICE. Có thể mở ứng dụng để in.')


def main(argv=None):
    parser = argparse.ArgumentParser(description='Sửa lỗi ONLYOFFICE không nhận queue IPP thiếu PPD; không cố định tên máy in.')
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--check', action='store_true', help='chỉ kiểm tra, không sửa')
    modes.add_argument('--repair', action='store_true', help='sửa queue đủ điều kiện (cần quyền quản trị)')
    modes.add_argument('--refresh-user', action='store_true', help='làm mới cấu hình in của người dùng khi ONLYOFFICE đã đóng')
    modes.add_argument('--restore', metavar='BACKUP_ID', help='hoàn tác một lần sửa')
    parser.add_argument('--queue', help='chỉ kiểm tra/sửa queue này; mặc định quét tất cả')
    parser.add_argument('--quiet', action='store_true', help='chỉ ghi thay đổi và lỗi')
    parser.add_argument('--automatic', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if not any((args.check, args.repair, args.refresh_user, args.restore)):
        args.check = True
    if args.automatic and not args.repair:
        parser.error('--automatic cần --repair')
    if args.queue and (args.restore or args.refresh_user):
        parser.error('--queue chỉ dùng với --check hoặc --repair')
    lock = None
    if args.repair or args.restore:
        if os.geteuid() != 0:
            raise RuntimeError('Cần quyền quản trị. Chạy sudo onlyoffice-printer-fix --repair')
        lock = os.open('/run/onlyoffice-printer-fix.lock', os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            if not args.quiet:
                print('Một phiên sửa máy in khác đang chạy. Thử lại sau.')
            return 0
    conn = local_connection()
    if args.refresh_user:
        refresh_user(conn, args.quiet)
        return 0
    if args.restore:
        restore(conn, args.restore)
        return 0
    printers = conn.getPrinters()
    if args.queue and args.queue not in printers:
        raise RuntimeError('Không tìm thấy queue: ' + args.queue)
    names = [args.queue] if args.queue else sorted(printers)
    errors = 0
    repaired = 0
    for name in names:
        try:
            attrs = conn.getPrinterAttributes(name)
            kind, message = classify(conn, name, attrs)
            if not args.quiet:
                print(f'{name}: {message}', flush=True)
            if kind == 'candidate' and args.repair:
                backup_id = repair_one(conn, name, attrs)
                repaired += 1
                print(f'Đã sửa {name}. Bản sao lưu: {backup_id}', flush=True)
        except Exception as exc:
            errors += 1
            reason = str(exc) if isinstance(exc, RuntimeError) else type(exc).__name__
            print(f'Chưa sửa được {name}: {reason}', file=sys.stderr, flush=True)
    if args.repair and (repaired or not args.quiet):
        print(f'Đã sửa {repaired} queue. Lưu tài liệu và mở lại ONLYOFFICE để nhận thay đổi.')
    return 1 if errors else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as exc:
        reason = str(exc) if isinstance(exc, RuntimeError) else type(exc).__name__
        print('Không thực hiện được: ' + reason, file=sys.stderr)
        sys.exit(1)
EOF
chmod 0755 /usr/lib/onlyoffice-printer-fix/fix.py

# 2. Lệnh CLI: /usr/bin/onlyoffice-printer-fix
cat << 'EOF' > /usr/bin/onlyoffice-printer-fix
#!/bin/sh
exec /usr/bin/python3 /usr/lib/onlyoffice-printer-fix/fix.py "$@"
EOF
chmod 0755 /usr/bin/onlyoffice-printer-fix

# 3. Giao diện Menu: /usr/bin/onlyoffice-printer-fix-ui
cat << 'EOF' > /usr/bin/onlyoffice-printer-fix-ui
#!/bin/sh
printf '%s\n' 'Sửa máy in ONLYOFFICE' 'Hãy lưu tài liệu và thoát ONLYOFFICE trước khi chạy.' ''
/usr/bin/pkexec /usr/bin/onlyoffice-printer-fix --repair
result=$?
if [ "$result" -eq 0 ]; then
    /usr/bin/onlyoffice-printer-fix --refresh-user
else
    printf '\n%s\n' 'Chưa hoàn tất. Xem thông báo ở trên; nếu bị hỏi, nhập mật khẩu quản trị trên máy này.'
fi
printf '\n%s' 'Nhấn Enter để đóng cửa sổ... '
read -r answer
exit "$result"
EOF
chmod 0755 /usr/bin/onlyoffice-printer-fix-ui

# 4. Systemd Service & Timer
cat << 'EOF' > /usr/lib/systemd/system/onlyoffice-printer-fix.service
[Unit]
Description=Repair missing PPD descriptions for ONLYOFFICE IPP printers
Wants=cups.service
After=cups.service network.target
ConditionPathExists=/run/cups/cups.sock

[Service]
Type=oneshot
ExecStart=/usr/bin/onlyoffice-printer-fix --repair --automatic --quiet
TimeoutStartSec=10min
UMask=0077
Nice=10
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK
EOF
chmod 0644 /usr/lib/systemd/system/onlyoffice-printer-fix.service

cat << 'EOF' > /usr/lib/systemd/system/onlyoffice-printer-fix.timer
[Unit]
Description=Check newly added ONLYOFFICE printer queues every two minutes

[Timer]
OnBootSec=30s
OnUnitInactiveSec=2min
AccuracySec=10s
Unit=onlyoffice-printer-fix.service

[Install]
WantedBy=timers.target
EOF
chmod 0644 /usr/lib/systemd/system/onlyoffice-printer-fix.timer

# 5. Desktop Shortcuts & Autostart
cat << 'EOF' > /usr/share/applications/onlyoffice-printer-fix.desktop
[Desktop Entry]
Type=Application
Name=Fix ONLYOFFICE Printers
Name[vi]=Sửa máy in ONLYOFFICE
Comment=Repair missing printer descriptions and refresh ONLYOFFICE printer settings
Comment[vi]=Tự tìm queue thiếu PPD và sửa cấu hình in ONLYOFFICE
Exec=/usr/bin/onlyoffice-printer-fix-ui
Icon=printer
Terminal=true
Categories=Settings;HardwareSettings;
StartupNotify=false
EOF
chmod 0644 /usr/share/applications/onlyoffice-printer-fix.desktop

cat << 'EOF' > /etc/xdg/autostart/onlyoffice-printer-fix.desktop
[Desktop Entry]
Type=Application
Name=ONLYOFFICE printer settings refresh
Exec=/usr/bin/onlyoffice-printer-fix --refresh-user --quiet
Icon=printer
Terminal=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=20
EOF
chmod 0644 /etc/xdg/autostart/onlyoffice-printer-fix.desktop

echo "⚙️ [3/4] Đang kích hoạt dịch vụ tự động quét và tiến hành sửa máy in..."
if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
  systemctl daemon-reload || true
  systemctl enable --now onlyoffice-printer-fix.timer >/dev/null 2>&1 || true
fi

/usr/bin/onlyoffice-printer-fix --repair || true

echo "🔄 [4/4] Đang làm mới cấu hình cache máy in cho tài khoản người dùng..."
REAL_USER="${SUDO_USER:-$(logname 2>/dev/null || true)}"
if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
  su - "$REAL_USER" -c "/usr/bin/onlyoffice-printer-fix --refresh-user" || true
fi

echo "✅ Hoàn tất! Hãy đóng hẳn ONLYOFFICE (nếu đang mở) và mở lại để nhận máy in."
