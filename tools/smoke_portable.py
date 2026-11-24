"""Extract the actual release ZIP, verify the macOS bundle, and start a demo.

Testing the build directory alone misses archive-induced signature/layout damage.
No browser is opened, no feeder is contacted, and no Gatekeeper exception is made.
"""
from pathlib import Path
import json
import os
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
import time
from urllib.request import ProxyHandler, Request, build_opener
import zipfile

from release_utils import ROOT, portable_name

archive_path = ROOT / "dist" / portable_name()
with tempfile.TemporaryDirectory(prefix="pet-feeder-package-") as temporary:
    folder = Path(temporary)
    if sys.platform == "darwin":
        with zipfile.ZipFile(archive_path) as archive:
            assert any(stat.S_ISLNK(info.external_attr >> 16) for info in archive.infolist()), "macOS symlinks were lost"
        subprocess.run(["ditto", "-x", "-k", str(archive_path), str(folder)], check=True)
        app = folder / "PetFeederLocalInstaller.app"
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        assert info["LSUIElement"] is True
        subprocess.run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)], check=True)
        exe = app / "Contents/MacOS/PetFeederLocalInstaller"
    else:
        with zipfile.ZipFile(archive_path) as archive:
            archive.extractall(folder)
            if os.name != "nt":
                for info in archive.infolist():
                    path = folder / info.filename
                    if path.is_file():
                        path.chmod((info.external_attr >> 16) & 0o777)
        exe = folder / "PetFeederLocalInstaller" / ("PetFeederLocalInstaller.exe" if os.name == "nt" else "PetFeederLocalInstaller")
    ready = folder / "ready.json"
    with tempfile.TemporaryFile(mode="w+b") as log:
        process = subprocess.Popen([str(exe), "--demo", "--no-browser", "--ready-file", str(ready)], stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 25
            while time.monotonic() < deadline:
                if ready.exists():
                    status = json.loads(ready.read_text())
                    if "error" in status:
                        raise SystemExit("Packaged startup failed: " + status.get("traceback", status["error"]))
                    url = status["url"]
                    opener = build_opener(ProxyHandler({}))
                    with opener.open(url, timeout=5) as response:
                        page = response.read().decode()
                    assert "Your feeder. Your network." in page and "Disconnected demo" in page
                    assert "Close installer" in page
                    csrf = re.search(r"const csrf='([^']+)'", page).group(1)
                    request = Request(url + "quit", data=b"{}", headers={
                        "Origin": url.rstrip("/"), "X-PFL-CSRF": csrf, "Content-Type": "application/json"})
                    with opener.open(request, timeout=5) as response:
                        assert json.load(response) == {"stopped": True}
                    assert process.wait(timeout=10) == 0
                    print("Extracted release ZIP: app/runtime, embedded assets, disconnected startup and clean shutdown verified")
                    break
                if process.poll() is not None:
                    log.seek(0)
                    raise SystemExit("Packaged wizard exited before startup: " + log.read().decode(errors="replace")[:1500])
                time.sleep(0.1)
            else:
                raise SystemExit("Packaged wizard startup timed out")
        finally:
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
