"""Shared release names; installer updates do not require feeder firmware changes."""
from pathlib import Path
import platform
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "installer"))
from pet_feeder_installer import __version__


def portable_name() -> str:
    system = {"Darwin": "macos", "Linux": "linux", "Windows": "windows"}[platform.system()]
    architecture = {"AMD64": "x86_64", "x86_64": "x86_64", "arm64": "arm64", "aarch64": "arm64"}[platform.machine()]
    return f"pet-feeder-local-{__version__}-{system}-{architecture}.zip"
