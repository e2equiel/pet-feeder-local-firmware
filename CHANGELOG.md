# Changelog

## Installer 0.2.2

- Replace the Mac Python bundle with a native Swift / SwiftUI app, requiring macOS 13+ and only Apple-provided runtime libraries.
- Add the original installer icon, a native review/confirmation screen, backup-folder picker, private token copy and a disconnected preview mode.
- Port exact-profile validation, double full backups, checked uploads, activation recovery and unchanged-schedule verification to Swift; cover the boundaries with native tests.
- Preserve the existing Windows/Linux and source installer. Firmware remains 0.2.0. No trusted Apple signing/notarization is claimed.
- Keep native on-device upgrade/restore validation explicitly pending; the existing Python installer's hardware validation does not establish the Swift port's behavior.

## Installer 0.2.1

- Package macOS as a double-clickable `.app` instead of a loose executable and Python directory.
- Preserve framework/resource symlinks and signatures in the Mac ZIP; verify and smoke-test the extracted archive in CI.
- Add `Start Installer.command` to the source ZIP for an existing trusted Python installation.
- Add a protected **Close installer** action; closing is refused during an active operation.
- Start the numeric loopback server without a reverse DNS lookup, avoiding macOS resolver delays.
- Prepare Developer ID signing and a notarization operator that refuses unsupported signatures before upload. Public builds remain ad-hoc signed and unnotarized until signing credentials are explicitly configured.
- Keep firmware overlay **0.2.0** unchanged. No MCU control, meal-table or camera protocol change is included in this installer update.

## 0.2.0

Initial community preview with a guided reversible installer, exact profile checks, private backups, local API/RTSP and LAN discovery. The macOS portable ZIP has a known distribution issue: Gatekeeper can block its separate Python libraries. Use the 0.2.1 source installer or app package and read its signing status.
