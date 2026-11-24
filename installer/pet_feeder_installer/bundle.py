"""Validate a locally bundled release before connecting to a device."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path

from .telnet import DeviceError

STOCK_SHA256 = "f499431d38ed3cb8a4607ee870f06461e14ccb9f6f6387137b0ded2f5191a499"
PARTITION_SIZES = (0x32000, 0x1000, 0x1000, 0xC000, 0x190000, 0x570000, 0xC0000)
FLASH_SIZE = sum(PARTITION_SIZES)
IMMUTABLE_SIZE = sum(PARTITION_SIZES[:-1])


@dataclass(frozen=True)
class Bundle:
    """A complete release. No vendor executable or device dump is bundled."""

    directory: Path
    version: str
    module_sha256: str

    @classmethod
    def load(cls, directory: Path) -> Bundle:
        try:
            manifest = json.loads((directory / "release.json").read_text())
            required = {"pf_local.so", "boot.sh", "uninstall.sh"}
            if (
                manifest["format"] != 1
                or manifest["stock_application_sha256"] != STOCK_SHA256
                or manifest["partition_sizes"] != list(PARTITION_SIZES)
                or set(manifest["files"]) != required
                or not isinstance(manifest["version"], str)
            ):
                raise ValueError("Unsupported release manifest")
            for name, expected in manifest["files"].items():
                actual = hashlib.sha256((directory / name).read_bytes()).hexdigest()
                if actual != expected:
                    raise ValueError("Release checksum mismatch")
            module = (directory / "pf_local.so").read_bytes()
            if module[:5] != b"\x7fELF\x01":
                raise ValueError("Expected a 32-bit ELF module")
            return cls(directory, manifest["version"], manifest["files"]["pf_local.so"])
        except (OSError, ValueError, KeyError, TypeError) as error:
            raise DeviceError("The installer bundle is incomplete or damaged. Download a fresh release ZIP.") from error
