"""Notarize an already Developer ID-signed app using a local keychain profile.

No Apple password, private key or API key is read into project code or logs.
This command deliberately refuses ad-hoc/development signatures before upload.
"""
from pathlib import Path
import argparse
import json
import subprocess
import tempfile

from release_utils import ROOT, portable_name


def validate_signing(app: Path) -> None:
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    details = subprocess.run(["codesign", "--display", "--verbose=4", str(app)],
                             check=True, capture_output=True, text=True).stderr
    if ("Authority=Developer ID Application:" not in details or "(runtime)" not in details
            or "Timestamp=" not in details or "Timestamp=none" in details):
        raise SystemExit("A Developer ID Application signature, hardened runtime and secure timestamp are required. Nothing was uploaded.")


def notarize(app: Path, profile: str, output: Path) -> None:
    validate_signing(app)
    with tempfile.TemporaryDirectory(prefix="pet-feeder-notary-") as temporary:
        archive = Path(temporary) / "submission.zip"
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)], check=True)
        result = subprocess.run(["xcrun", "notarytool", "submit", str(archive), "--keychain-profile", profile,
                                 "--wait", "--output-format", "json"], capture_output=True, text=True, check=True)
        status = json.loads(result.stdout)
        if status.get("status") != "Accepted":
            raise SystemExit("Apple did not accept this build. Inspect its notarization log locally before distributing it.")
    subprocess.run(["xcrun", "stapler", "staple", str(app)], check=True)
    subprocess.run(["xcrun", "stapler", "validate", str(app)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    subprocess.run(["spctl", "--assess", "--type", "execute", "--verbose=2", str(app)], check=True)
    # Use the same archive format as the tested portable builder, after stapling.
    from build_portable import archive_macos, write_checksum
    archive_macos(app, output, "Developer ID signed, notarized by Apple, ticket stapled and Gatekeeper assessment passed.\n")
    write_checksum(output)
    print("Notarized archive and checksum prepared: " + str(output))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True, help="Existing notarytool keychain profile name")
    parser.add_argument("--app", type=Path, help="Optional app to submit; by default extract the current ZIP into a temporary build directory")
    parser.add_argument("--output", type=Path, default=ROOT / "dist" / portable_name())
    args = parser.parse_args()
    if args.app:
        notarize(args.app.resolve(), args.profile, args.output.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix="pet-feeder-signing-") as temporary:
            subprocess.run(["ditto", "-x", "-k", str(ROOT / "dist" / portable_name()), temporary], check=True)
            notarize(Path(temporary) / "PetFeederLocalInstaller.app", args.profile, args.output.resolve())
