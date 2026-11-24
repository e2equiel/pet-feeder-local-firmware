#!/usr/bin/env python3
"""Package original project code only; never include vendor dumps or secrets."""
from pathlib import Path
import hashlib
import json
import shutil
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "installer"))
from pet_feeder_installer.bundle import PARTITION_SIZES, STOCK_SHA256, Bundle
from pet_feeder_installer import __version__

def build() -> Path:
    bundle = ROOT / "bundle"
    bundle.mkdir(exist_ok=True)
    shutil.copyfile(ROOT / "build/pf_local.so", bundle / "pf_local.so")
    for name in ("boot.sh", "uninstall.sh"):
        shutil.copyfile(ROOT / "scripts" / name, bundle / name)
    manifest = {"format": 1, "version": __version__, "stock_application_sha256": STOCK_SHA256,
                "partition_sizes": list(PARTITION_SIZES),
                "files": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(bundle.iterdir()) if p.name != "release.json"}}
    (bundle / "release.json").write_text(json.dumps(manifest, indent=2) + "\n")
    Bundle.load(bundle)
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    output = dist / f"pet-feeder-local-{__version__}-source-installer.zip"
    paths = [ROOT / "install.py", ROOT / "README.md", ROOT / "LICENSE"]
    paths += [p for d in ("bundle", "installer", "docs") for p in (ROOT / d).rglob("*")
              if p.is_file() and "__pycache__" not in p.parts and "tests" not in p.parts]
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(paths):
            archive.write(path, path.relative_to(ROOT))
    (dist / (output.name + ".sha256")).write_text(hashlib.sha256(output.read_bytes()).hexdigest() + "  " + output.name + "\n")
    return output

if __name__ == "__main__":
    print(build())
