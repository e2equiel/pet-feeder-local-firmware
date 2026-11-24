"""Start the packaged wizard in disconnected demo mode on each build OS."""
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from urllib.request import ProxyHandler, build_opener

root=Path(__file__).resolve().parents[1]
exe=root/'dist/PetFeederLocalInstaller'/('PetFeederLocalInstaller.exe' if sys.platform=='win32' else 'PetFeederLocalInstaller')
with tempfile.TemporaryFile(mode='w+b') as log:
    process=subprocess.Popen([str(exe),'--demo','--no-browser'],stdout=log,stderr=log)
    try:
        deadline=time.monotonic()+25
        while time.monotonic()<deadline:
            log.seek(0);lines=log.read().decode(errors='replace').splitlines()
            addresses=[line.split()[-1] for line in lines if line.startswith('Open the installer at http://127.0.0.1:')]
            if addresses:
                with build_opener(ProxyHandler({})).open(addresses[0],timeout=5) as response:page=response.read().decode()
                assert 'Your feeder. Your network.' in page and 'Disconnected demo' in page
                print('Portable installer and embedded assets loaded in disconnected demo mode')
                break
            if process.poll() is not None:raise SystemExit('Portable installer exited before the wizard started')
            time.sleep(0.1)
        else:raise SystemExit('Portable wizard startup timed out')
    finally:
        process.terminate();process.wait(timeout=10)
