#!/usr/bin/env python3
"""Leaf OS ISO edition: the local helper server.

Serves the Leaf OS desktop on http://127.0.0.1:8080 and gives it a few things a web
page can't do by itself: real Shut down / Restart, the Terminal's network commands,
the Downloads app (files Chromium saved), a real Chromium window for logins, and a
crash log.

Settings for testing on another computer (all optional):
  LEAFOS_ROOT=/path/to/leafos  LEAFOS_PORT=8080  LEAFOS_DOWNLOADS=~/Downloads  LEAFOS_TEST=1
"""
import functools
import http.server
import json
import mimetypes
import os
import shutil
import subprocess
import time
import urllib.parse

ROOT = os.environ.get("LEAFOS_ROOT", "/opt/leafos")
PORT = int(os.environ.get("LEAFOS_PORT", "8080"))
HOME = os.path.expanduser("~")
DOWNLOADS = os.path.realpath(os.environ.get("LEAFOS_DOWNLOADS", os.path.join(HOME, "Downloads")))
CHROMIUM_LOG = os.path.join(HOME, ".leafos-chromium.log")
CRASHES = os.path.join(HOME, ".leafos-crashes")
TEST = os.environ.get("LEAFOS_TEST") == "1"
ALLOWED_HOSTS = {f"127.0.0.1:{PORT}", f"localhost:{PORT}"}

CHECKS = [
    ("network cards", ["ip", "-br", "link"]),
    ("addresses", ["ip", "-4", "-br", "addr"]),
    ("routes", ["ip", "route"]),
    ("dns servers", ["cat", "/etc/resolv.conf"]),
    ("networkmanager", ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device"]),
    ("dns lookup", ["getent", "hosts", "api.open-meteo.com"]),
    ("https test", ["curl", "-sS", "-m", "8", "-o", "/dev/null", "-w", "HTTP %{http_code}\n",
                    "https://api.open-meteo.com/v1/forecast?latitude=40&longitude=-3&current=temperature_2m"]),
]
PARTIAL = (".crdownload", ".part", ".download", ".tmp")


def run(cmd, timeout=12):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return (r.stdout + r.stderr).strip() or "(no output)"
    except Exception as e:  # noqa: BLE001
        return f"error: {e}"


def meminfo():
    info = {}
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                k, v = line.split(":", 1)
                info[k] = int(v.split()[0]) * 1024
    except OSError:
        pass
    return info


def uptime():
    try:
        with open("/proc/uptime") as f:
            return float(f.read().split()[0])
    except (OSError, ValueError):
        return 0.0


def tail(path, lines=80):
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            f.seek(max(0, f.tell() - 64000))
            return b"\n".join(f.read().splitlines()[-lines:]).decode("utf-8", "replace")
    except OSError:
        return "(no log yet)"


def download_path(name):
    """The full path of a file in Downloads, or None if the name is not a plain file name there."""
    name = os.path.basename(str(name or ""))
    if not name or name in (".", "..") or name.startswith("."):
        return None
    path = os.path.realpath(os.path.join(DOWNLOADS, name))
    if os.path.dirname(path) != DOWNLOADS or not os.path.isfile(path):
        return None
    return path


def list_downloads():
    os.makedirs(DOWNLOADS, exist_ok=True)
    files = []
    for entry in os.scandir(DOWNLOADS):
        if entry.name.startswith(".") or not entry.is_file(follow_symlinks=False):
            continue
        st = entry.stat()
        files.append({"name": entry.name, "size": st.st_size, "mtime": int(st.st_mtime),
                      "partial": entry.name.lower().endswith(PARTIAL)})
    files.sort(key=lambda f: f["mtime"], reverse=True)
    usage = shutil.disk_usage(DOWNLOADS)
    return {"dir": DOWNLOADS, "free": usage.free, "total": usage.total, "files": files}


def crash_times():
    try:
        with open(CRASHES) as f:
            return [int(x) for x in f.read().split() if x.isdigit()]
    except OSError:
        return []


class LeafHandler(http.server.SimpleHTTPRequestHandler):
    def send_body(self, body, ctype, code=200, extra=None):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def send_text(self, text, code=200):
        self.send_body(text, "text/plain; charset=utf-8", code)

    def send_json(self, data, code=200):
        self.send_body(json.dumps(data), "application/json", code)

    def host_ok(self):
        # Only this computer's own address (blocks "DNS rebinding" tricks by websites)
        if self.headers.get("Host", "") in ALLOWED_HOSTS:
            return True
        self.send_text("forbidden", 403)
        return False

    def do_GET(self):
        if not self.host_ok():
            return
        path = urllib.parse.urlsplit(self.path).path
        if path == "/netstatus":
            self.send_text("\n\n".join(f"== {t} ==\n{run(c)}" for t, c in CHECKS))
        elif path == "/api/downloads":
            self.send_json(list_downloads())
        elif path.startswith("/dl/"):
            self.serve_download(urllib.parse.unquote(path[4:]))
        elif path == "/api/sysinfo":
            m = meminfo()
            usage = shutil.disk_usage(HOME)
            self.send_json({
                "mem_total": m.get("MemTotal", 0), "mem_available": m.get("MemAvailable", 0),
                "swap_total": m.get("SwapTotal", 0), "swap_free": m.get("SwapFree", 0),
                "disk_total": usage.total, "disk_free": usage.free,
                "kernel": os.uname().release, "uptime": uptime(),
            })
        elif path == "/api/crashinfo":
            times = crash_times()
            now = time.time()
            self.send_json({"last": times[-1] if times else 0, "today": len([t for t in times if now - t < 86400])})
        elif path == "/api/crashlog":
            m = meminfo()
            parts = [
                "== memory ==\n" + f"total {m.get('MemTotal', 0) // 1048576} MB, available {m.get('MemAvailable', 0) // 1048576} MB, "
                f"swap free {m.get('SwapFree', 0) // 1048576} of {m.get('SwapTotal', 0) // 1048576} MB",
                "== crashes ==\n" + ("\n".join(time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t)) for t in crash_times()[-10:]) or "none"),
                "== kernel (out of memory / crashes) ==\n" + ("(test mode)" if TEST else "\n".join(
                    line for line in run(["sudo", "-n", "dmesg"], 10).splitlines()
                    if any(w in line.lower() for w in ("oom", "killed process", "segfault", "out of memory", "chromium"))
                )[-4000:] or "nothing found"),
                "== chromium log (last lines) ==\n" + tail(CHROMIUM_LOG, 60),
            ]
            self.send_text("\n\n".join(parts))
        else:
            super().do_GET()

    def serve_download(self, name):
        p = download_path(name)
        if not p:
            self.send_text("file not found", 404)
            return
        ctype = mimetypes.guess_type(p)[0] or "application/octet-stream"
        if ctype in ("text/plain", "text/markdown", "text/csv", "application/json"):
            ctype += "; charset=utf-8"
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        disposition = "attachment" if query.get("download") else "inline"
        size = os.path.getsize(p)
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(size))
        self.send_header("Content-Disposition", f"{disposition}; filename*=UTF-8''{urllib.parse.quote(os.path.basename(p))}")
        # Downloaded web pages run in a sealed box: they can't touch Leaf OS or this server
        self.send_header("Content-Security-Policy", "sandbox allow-scripts allow-popups allow-forms allow-modals")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        with open(p, "rb") as f:
            shutil.copyfileobj(f, self.wfile, 256 * 1024)

    def do_POST(self):
        if not self.host_ok():
            return
        # The custom header blocks requests coming from other websites
        if self.headers.get("X-Leaf") != "1":
            self.send_text("forbidden", 403)
            return
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(min(length, 8192)).decode("utf-8", "replace").strip()
        if self.path in ("/power/off", "/power/reboot"):
            self.send_text("ok")
            action = "poweroff" if self.path.endswith("off") else "reboot"
            if not TEST:
                subprocess.Popen(["sudo", "-n", "systemctl", action])
        elif self.path == "/open":
            # A real, separate Chromium window (logins, games, anything)
            if not (body.startswith("http://") or body.startswith("https://")):
                self.send_text("bad url", 400)
                return
            if TEST:
                self.send_text("ok (test)")
                return
            try:
                subprocess.Popen([
                    "chromium", "--user-data-dir=" + os.path.join(HOME, ".leafos-web"),
                    "--no-first-run", "--start-maximized", "--password-store=basic",
                    "--disable-gpu", "--disk-cache-size=33554432", "--new-window", body,
                ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
                self.send_text("ok")
            except OSError as e:
                self.send_text(f"could not start chromium: {e}", 500)
        elif self.path == "/api/downloads/delete":
            p = download_path(body)
            if not p:
                self.send_text("file not found", 404)
                return
            try:
                os.remove(p)
                self.send_text("ok")
            except OSError as e:
                self.send_text(f"could not delete: {e}", 500)
        elif self.path == "/netfix":
            if TEST:
                self.send_text("ok (test)")
                return
            out = run(["sudo", "-n", "systemctl", "restart", "NetworkManager"], 20)
            out += "\n" + run(["sudo", "-n", "/usr/local/sbin/leafos-netfix", "now"], 120)
            self.send_text(out)
        else:
            self.send_text("not found", 404)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    os.makedirs(DOWNLOADS, exist_ok=True)
    mimetypes.add_type("text/markdown", ".md")
    handler = functools.partial(LeafHandler, directory=ROOT)
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), handler).serve_forever()
