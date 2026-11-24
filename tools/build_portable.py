"""Build native Swift on macOS and portable Python bundles on Windows/Linux."""
from pathlib import Path
import hashlib
import platform
import subprocess
import zipfile

from release_utils import ROOT, __version__, portable_name


def build() -> Path:
    macos = platform.system() == "Darwin"
    if macos:
        if (ROOT / "native/macos/VERSION").read_text().strip() != __version__:
            raise SystemExit("Native and portable installer versions must match.")
        subprocess.run(["/bin/sh", str(ROOT / "tools/build_macos_native.sh")], check=True, cwd=ROOT)
        return ROOT / "dist" / portable_name()
    command = ["pyinstaller", "--noconfirm", "--clean", "--onedir", "--name", "PetFeederLocalInstaller",
               "--paths", str(ROOT / "installer"), "--add-data", str(ROOT / "bundle") + ":bundle",
               "--add-data", str(ROOT / "installer/pet_feeder_installer/assets") + ":pet_feeder_installer/assets"]
    command.append(str(ROOT / "install.py"))
    subprocess.run(command, check=True, cwd=ROOT)
    output = ROOT / "dist" / portable_name()
    if output.exists():
        output.unlink()
    with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted((ROOT / "dist/PetFeederLocalInstaller").rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(ROOT / "dist"))
        for path in (ROOT / "README.md", ROOT / "LICENSE"):
            archive.write(path, path.name)
    write_checksum(output)
    return output


def write_checksum(output: Path) -> None:
    (output.parent / (output.name + ".sha256")).write_text(
        hashlib.sha256(output.read_bytes()).hexdigest() + "  " + output.name + "\n")


def archive_macos(app: Path, output: Path, status: str) -> None:
    if output.exists():
        output.unlink()
    subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(output)], check=True)
    with zipfile.ZipFile(output, "a", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("SIGNING-STATUS.txt", status)
        for path in (ROOT / "README.md", ROOT / "LICENSE"):
            archive.write(path, path.name)


if __name__ == "__main__":
    print(build())
