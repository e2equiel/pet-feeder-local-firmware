"""A loopback-only installation wizard using the Python standard library."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import secrets
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from socketserver import TCPServer
import sys
import threading
import subprocess
import webbrowser

from . import __version__, FIRMWARE_VERSION
from .bundle import Bundle
from .device import Installer
from .telnet import DeviceError, Telnet, local_address


class Wizard:
    def __init__(self, bundle: Bundle | None, backups: Path, *, demo: bool = False) -> None:
        self.bundle = bundle
        self.backups = backups
        self.demo = demo
        self.csrf = secrets.token_urlsafe(32)
        self.lock = threading.Lock()
        self.executor = ThreadPoolExecutor(max_workers=1)
        self.installer: Installer | None = None
        self.status: dict[str, object] = {"stage": "welcome", "message": "Ready to check one feeder."}
        self.busy = False

    def progress(self, stage: str, message: str) -> None:
        with self.lock:
            self.status.update(stage=stage, message=message)

    def submit(self, action: str, data: dict[str, object]) -> None:
        with self.lock:
            if self.busy:
                raise DeviceError("An operation is already running. Wait for it to finish.")
            if action not in {"inspect", "install", "restore"}:
                raise DeviceError("Unknown operation.")
            if action != "inspect" and self.status.get("stage") != "review":
                raise DeviceError("Check and review the selected feeder first.")
            self.busy = True
            self.status = {"stage": "checking", "message": "Starting…"}
        self.executor.submit(self.run, action, data)

    def run(self, action: str, data: dict[str, object]) -> None:
        try:
            if self.demo:
                self.progress("review", "Demo only — no device connection was made.")
                with self.lock:
                    self.status["details"] = {"model": "V330L-DU4L-VS", "stock_version": "68.00.09",
                                              "version_to_install": FIRMWARE_VERSION, "upgrade": False}
                return
            if action == "inspect":
                if self.installer:
                    self.installer.transport.close()
                host = local_address(str(data.get("address", "")))
                if self.bundle is None:
                    raise DeviceError("No release bundle was found. Download the complete installer ZIP.")
                self.installer = Installer(Telnet(host, str(data.get("password", ""))), self.bundle, self.progress)
                # A broken old API must still allow the Restore operation.
                details = self.installer.inspect(require_api=False)
                with self.lock:
                    self.status.update(stage="review", message="This exact firmware is supported.", details=details)
            elif self.installer is not None:
                try:
                    if action == "install":
                        result = self.installer.install(self.backups)
                        with self.lock:
                            self.status["result"] = result
                    else:
                        self.installer.restore()
                finally:
                    self.installer.transport.close()
                    self.installer = None
            else:
                raise DeviceError("Check the feeder again before continuing.")
        except (DeviceError, OSError, ValueError):
            error = sys.exc_info()[1]
            message = str(error) if isinstance(error, DeviceError) else "Could not complete the operation. Check the feeder's power, address and Wi-Fi."
            self.progress("error", message)
        except Exception:
            # Do not serialize a traceback or arbitrary network exception: it
            # can contain device credentials. Keep the private backups locally.
            self.progress("error", "Unexpected installation error. Keep your backups and report the stage, without credentials.")
        finally:
            with self.lock:
                self.busy = False


def make_server(wizard: Wizard) -> ThreadingHTTPServer:
    page = (Path(__file__).parent / "assets" / "index.html").read_text()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_: object) -> None:
            pass

        def reply(self, status: int, payload: bytes, content_type: str) -> None:
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; frame-ancestors 'none'; connect-src 'self'")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)

        def valid_host(self) -> bool:
            return self.headers.get("Host") == f"127.0.0.1:{self.server.server_port}"

        def do_GET(self) -> None:
            if not self.valid_host():
                self.reply(403, b"Forbidden", "text/plain")
            elif self.path == "/":
                self.reply(200, page.replace("__CSRF__", wizard.csrf).replace("__INSTALLER_VERSION__", __version__).replace("__DEMO__", "true" if wizard.demo else "false").encode(), "text/html; charset=utf-8")
            elif self.path == "/status" and secrets.compare_digest(self.headers.get("X-PFL-CSRF", ""), wizard.csrf):
                with wizard.lock:
                    payload = json.dumps({**wizard.status, "busy": wizard.busy}).encode()
                self.reply(200, payload, "application/json")
            else:
                self.reply(404, b"Not found", "text/plain")

        def do_POST(self) -> None:
            origin = f"http://127.0.0.1:{self.server.server_port}"
            if (not self.valid_host() or self.headers.get("Origin") != origin
                or not secrets.compare_digest(self.headers.get("X-PFL-CSRF", ""), wizard.csrf)):
                self.reply(403, b"Forbidden", "text/plain")
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length < 4096:
                    raise ValueError
                data = json.loads(self.rfile.read(length))
                if not isinstance(data, dict):
                    raise ValueError
                if self.path == "/quit":
                    with wizard.lock:
                        if wizard.busy:
                            raise DeviceError("Wait for the current operation to finish before closing the installer.")
                    self.reply(200, b'{"stopped":true}', "application/json")
                    threading.Thread(target=self.server.shutdown, daemon=True).start()
                    return
                wizard.submit(self.path.removeprefix("/"), data)
                self.reply(202, b"{}", "application/json")
            except (ValueError, DeviceError) as error:
                self.reply(400, json.dumps({"error": str(error) if isinstance(error, DeviceError) else "Invalid request"}).encode(), "application/json")

    class LoopbackServer(ThreadingHTTPServer):
        def server_bind(self) -> None:
            # HTTPServer.server_bind calls getfqdn, which can wait for DNS on
            # macOS even for localhost. This service only uses numeric loopback.
            TCPServer.server_bind(self)
            self.server_name, self.server_port = self.server_address[:2]

    return LoopbackServer(("127.0.0.1", 0), Handler)


def main() -> None:
    parser = argparse.ArgumentParser(description="Install the reversible Pet Feeder Local overlay on one supported feeder.")
    parser.add_argument("--bundle", type=Path)
    parser.add_argument("--backups", type=Path, default=Path.home() / "Documents" / "PetFeederLocalBackups")
    parser.add_argument("--demo", action="store_true", help="Display a disconnected demo; no device is contacted")
    parser.add_argument("--no-browser", action="store_true")
    parser.add_argument("--ready-file", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.ready_file and not (args.demo and args.no_browser):
        parser.error("--ready-file is only available for a disconnected --demo --no-browser check")
    root = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parents[2]))
    bundle_path = args.bundle or root / "bundle"
    try:
        bundle = None if args.demo else Bundle.load(bundle_path)
    except DeviceError as error:
        parser.exit(1, str(error) + "\n")
    wizard = Wizard(bundle, args.backups, demo=args.demo)
    server = make_server(wizard)
    url = f"http://127.0.0.1:{server.server_port}/"
    if sys.stdout is not None:
        print("Open the installer at " + url, flush=True)
    if args.ready_file:
        args.ready_file.write_text(json.dumps({"url": url}) + "\n")
    if not args.no_browser:
        if sys.platform == "darwin":
            # LaunchServices opens the default browser without Apple Events automation.
            subprocess.Popen(["/usr/bin/open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        wizard.executor.shutdown(wait=True)
        if wizard.installer:
            wizard.installer.transport.close()


if __name__ == "__main__":
    main()
