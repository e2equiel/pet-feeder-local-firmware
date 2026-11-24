"""Build a portable installer, preserving macOS app signatures and symlinks."""
from pathlib import Path
import hashlib
import os
import platform
import plistlib
import subprocess
import zipfile

from release_utils import ROOT, __version__, portable_name


def build() -> Path:
    macos = platform.system() == "Darwin"
    identity = os.environ.get("MACOS_SIGNING_IDENTITY", "") if macos else ""
    command = ["pyinstaller", "--noconfirm", "--clean", "--onedir", "--name", "PetFeederLocalInstaller",
               "--paths", str(ROOT / "installer"), "--add-data", str(ROOT / "bundle") + ":bundle",
               "--add-data", str(ROOT / "installer/pet_feeder_installer/assets") + ":pet_feeder_installer/assets"]
    if macos:
        command += ["--windowed", "--osx-bundle-identifier", "io.github.e2equiel.pet-feeder-local.installer"]
        if identity:
            command += ["--codesign-identity", identity]
    command.append(str(ROOT / "install.py"))
    subprocess.run(command, check=True, cwd=ROOT)
    output = ROOT / "dist" / portable_name()
    if output.exists():
        output.unlink()
    if macos:
        app = ROOT / "dist/PetFeederLocalInstaller.app"
        info_path = app / "Contents/Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info.update(CFBundleDisplayName="Pet Feeder Local Installer", CFBundleName="Pet Feeder Local Installer",
                    CFBundleShortVersionString=__version__, CFBundleVersion=__version__, LSUIElement=True)
        info_path.write_bytes(plistlib.dumps(info))
        # PyInstaller signs all embedded Mach-O files. Re-seal the outer bundle
        # after updating its Info.plist; no security exceptions are requested.
        sign = ["codesign", "--force", "--sign", identity or "-"]
        if identity:
            sign += ["--options", "runtime", "--timestamp"]
        subprocess.run([*sign, str(app)], check=True)
        subprocess.run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)], check=True)
        if identity:
            details = subprocess.run(["codesign", "--display", "--verbose=4", str(app)],
                                     check=True, capture_output=True, text=True).stderr
            if "Authority=Developer ID Application:" not in details:
                raise SystemExit("MACOS_SIGNING_IDENTITY must resolve to a Developer ID Application certificate.")
        # zipfile/rglob flattened framework symlinks in 0.2.0. ditto preserves
        # the actual app layout, file modes and code-signing resource envelope.
        archive_macos(app, output, "Developer ID signed; notarization still required.\n" if identity else
                      "Ad-hoc signed app bundle. Not Developer ID signed or notarized. macOS can still block this app.\n"
                      "Use the source installer with a trusted Python installation as an alternative.\n")
    else:
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
