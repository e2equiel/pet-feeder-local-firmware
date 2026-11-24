# macOS packaging and signing

## Current status

Installer 0.2.2 is a native **Swift / SwiftUI** app for macOS 13+. Its single Mac executable links only to Apple-provided system frameworks and Swift libraries. It includes the Linux overlay as a resource, but no Python interpreter, Python extension, third-party Mac library, browser or local web server. Windows/Linux and the optional source installer retain their existing Python implementation.

The build seals the app and archives it with macOS `ditto`. CI extracts the actual ZIP, verifies `codesign --verify --deep --strict`, checks its linked libraries and embedded release/icon, and runs the native boundary suite on both Mac architectures. GUI preview and automated core checks are separate from an on-device upgrade.

The public build currently has an **ad-hoc integrity signature**. It is **not Developer ID signed or notarized by Apple**. Passing a local signature check does not mean Gatekeeper trusts the publisher, and does not promise zero warnings on another Mac. The old 0.2.0 loose executable/Python directory should not be used to approve libraries individually.

Removing Python eliminates approvals for its separate native extensions. It does **not** eliminate Gatekeeper's publisher check. An unnotarized native app can still be blocked as an unidentified developer. The operating system can also request local-network access and permission to save private backups; these are separate privacy controls, not Python-library approvals. Do not promise exactly one prompt on every macOS version or managed Mac.

The optional source-installer alternative uses an existing trusted Python from python.org or Homebrew. Extract its complete ZIP and open `Start Installer.command`. An initial approval of the launcher may still be required by macOS. The native app itself does not need Python.

No script in this project removes quarantine metadata, disables Gatekeeper, installs a custom root certificate, or changes system security policies.

## Trusted public distribution

Apple requires a **Developer ID Application** certificate, hardened runtime, a secure timestamp and notarization for the normal trusted distribution path outside the App Store. A free Apple developer account or a self-signed certificate does not provide Developer ID. The standard Apple Developer Program costs USD 99 per membership year; regional pricing and eligible organizational fee waivers are described by Apple. No membership purchase or signing credential has been configured by this project.

References: [Developer ID](https://developer.apple.com/developer-id/), [notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [membership terms and fee](https://developer.apple.com/programs/enroll/), [opening apps safely](https://support.apple.com/en-us/102445).

## Build and notarize after credentials are available

Keep certificates and private keys in the macOS keychain. The scripts never read or commit key material, Apple passwords or API keys. Prepare the existing notarytool keychain profile interactively using Apple's instructions.

```sh
# Use the exact Developer ID Application identity already in your keychain.
MACOS_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
  sh tools/build_macos_native.sh

# PROFILE is an existing notarytool keychain profile name, not a password.
python3 tools/notarize_macos.py --profile PROFILE
```

The operator extracts the current ZIP into a temporary build directory (or accepts an explicit `--app` path). It refuses an ad-hoc/development signature, missing hardened runtime or missing secure timestamp **before uploading anything**. It submits only the app bundle, requires Apple's `Accepted` result, staples and validates the ticket, checks Gatekeeper assessment, and rebuilds the ZIP and checksum after stapling. Re-test that final archive before publication. A publisher must explicitly configure and authorize these credentials; ordinary CI builds do not attempt notarization.

Building the app in a temporary directory also avoids Finder/File Provider metadata being attached to a bundle during sealing in a synced Documents directory. The build never removes quarantine or changes security policy.

The notarization path is prepared but has not been exercised against Apple because there is no Developer ID certificate or membership configured. Do not label an artifact as notarized until the full operator and final archive verification succeed.
