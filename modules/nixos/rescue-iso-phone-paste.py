"""phone-paste: type into this machine from your phone.

Shows a QR code for a one-time page on this machine's network address.
Whatever is submitted there is printed to stdout, then the server exits.
Used by ai-login for Claude's login code; also handy for long passwords
or commands (e.g. `phone-paste | wl-copy`).

The page needs the random token in its URL, takes one submission, binds
only the address of the default route, and gives up after 15 minutes.
"""

import html
import secrets
import socket
import subprocess
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs

PORT = 8765
TIMEOUT_S = 15 * 60

PAGE = """<!doctype html>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>phone-paste</title>
<style>
  body {{ font: 18px system-ui, sans-serif; margin: 1.5rem; }}
  textarea {{ width: 100%; height: 9rem; font: 16px monospace; }}
  button {{ font-size: 1.1rem; padding: .6rem 1.4rem; margin-top: .8rem; }}
</style>
<h3>Send text to {host}</h3>
<form method="post">
  <textarea name="text" autofocus placeholder="Paste here"></textarea>
  <button type="submit">Send</button>
</form>
"""

DONE = """<!doctype html>
<meta name="viewport" content="width=device-width, initial-scale=1">
<p style="font: 18px system-ui, sans-serif">Sent. You can close this page.</p>
"""


def default_route_ip():
    # the address other devices on this network reach us at
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.connect(("1.1.1.1", 9))
        return s.getsockname()[0]


def main():
    try:
        ip = default_route_ip()
    except OSError:
        sys.exit("phone-paste: no network. Plug in a phone with USB tethering, or connect with nmtui.")

    token = secrets.token_urlsafe(16)
    url = f"http://{ip}:{PORT}/{token}"
    received = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def _reply(self, code, body):
            data = body.encode()
            self.send_response(code)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            if self.path != f"/{token}":
                return self._reply(404, "not found")
            self._reply(200, PAGE.format(host=html.escape(socket.gethostname())))

        def do_POST(self):
            if self.path != f"/{token}" or received:
                return self._reply(404, "not found")
            length = min(int(self.headers.get("Content-Length", 0)), 64 * 1024)
            form = parse_qs(self.rfile.read(length).decode(errors="replace"))
            received.append(form.get("text", [""])[0].strip())
            self._reply(200, DONE)
            threading.Thread(target=self.server.shutdown).start()

    server = HTTPServer((ip, PORT), Handler)
    subprocess.run(["sudo", "nixos-firewall-tool", "open", "tcp", str(PORT)], check=True)
    try:
        subprocess.run(["qrencode", "-t", "ansiutf8", url], stdout=sys.stderr, check=False)
        print(f"Scan with your phone, or open: {url}", file=sys.stderr)
        timer = threading.Timer(TIMEOUT_S, server.shutdown)
        timer.start()
        server.serve_forever()
        timer.cancel()
    finally:
        server.server_close()
        subprocess.run(["sudo", "nixos-firewall-tool", "reset"], check=False)

    if not received:
        sys.exit("phone-paste: timed out with nothing sent")
    print(received[0])


if __name__ == "__main__":
    main()
