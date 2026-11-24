# macOS packaging and signing

## Current status

Installer 0.2.1 provides a normal `.app` bundle. It preserves the framework/resource symlinks and code-signing envelope when archiving with macOS `ditto`. CI extracts the actual release ZIP, verifies the complete bundle with `codesign --verify --deep --strict`, and starts its disconnected demo. Testing only the build directory missed the end-user archive/Gatekeeper path in 0.2.0.

The public build currently has an **ad-hoc integrity signature**. It is **not Developer ID signed or notarized by Apple**. Passing a local signature check does not mean Gatekeeper trusts the publisher, and does not promise zero warnings on another Mac. The old 0.2.0 loose executable/Python directory should not be used to approve libraries individually.

The free source-installer alternative uses an existing trusted Python from python.org or Homebrew. Extract its complete ZIP and open `Start Installer.command`. It does not bundle a second Mach-O Python runtime. An initial approval of the launcher may still be required by macOS.

No script in this project removes quarantine metadata, disables Gatekeeper, installs a custom root certificate, or changes system security policies.

## Trusted public distribution

Apple requires a **Developer ID Application** certificate, hardened runtime, a secure timestamp and notarization for the normal trusted distribution path outside the App Store. A free Apple developer account or a self-signed certificate does not provide Developer ID. The standard Apple Developer Program costs USD 99 per membership year; regional pricing and eligible organizational fee waivers are described by Apple. No membership purchase or signing credential has been configured by this project.

References: [Developer ID](https://developer.apple.com/developer-id/), [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [membership terms and fee](https://developer.apple.com/programs/enroll/), [PyInstaller signing support](https://pyinstaller.org/en/stable/feature-notes.html#macos-binary-code-signing).

## Build and notarize after credentials are available

Keep certificates and private keys in the macOS keychain. The scripts never read or commit key material, Apple passwords or API keys. Prepare the existing notarytool keychain profile interactively using Apple's instructions.

```sh
# Use the exact Developer ID Application identity already in your keychain.
MACOS_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  python3 tools/build_portable.py

# PROFILE is an existing notarytool keychain profile name, not a password.
python3 tools/notarize_macos.py --profile PROFILE
```

The operator refuses an ad-hoc/development signature, missing hardened runtime or missing secure timestamp **before uploading anything**. It submits only the app bundle, requires Apple's `Accepted` result, staples and validates the ticket, checks Gatekeeper assessment, and rebuilds the ZIP and checksum after stapling. Re-test that final archive before publication. A publisher must explicitly configure and authorize these credentials; ordinary CI builds do not attempt notarization.

The notarization path is prepared but has not been exercised against Apple because there is no Developer ID certificate or membership configured. Do not label an artifact as notarized until the full operator and final archive verification succeed.
