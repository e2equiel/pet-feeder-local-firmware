# Changelog

## Installer 0.3.0

- Redesign the native Mac app and portable wizard with the original icon, a three-step layout, neutral surfaces and adaptive light/dark colors.
- Clarify single-device checks, private backups, installation confirmation and Home Assistant setup; add visible keyboard focus and responsive portable layouts.
- Keep portable demo installation disabled, require confirmation for stock restoration, and show a dedicated restored state.
- Keep the native app free of Python and third-party runtimes. Firmware overlay remains 0.2.0; no working device needs reinstalling.
- Validate the redesign with disconnected fixtures and existing installer boundary tests. This release adds no hardware, feeding, battery or power-loss claim.

## Installer 0.2.2

- Replace the Mac Python bundle with a native Swift / SwiftUI app, requiring macOS 13+ and only Apple-provided runtime libraries.
- Add the original installer icon, a native review/confirmation screen, backup-folder picker, private token copy and a disconnected preview mode.
- Port exact-profile validation, double full backups, checked uploads, activation recovery and unchanged-schedule verification to Swift; cover the boundaries with native tests.
- Recognize real Telnet CRLF completion frames with UTF-16 regular-expression matching and include a hardware-derived regression fixture.
- Retain the native backup-folder dialog until completion and update the selected destination on the main queue.
- Preserve the existing Windows/Linux and source installer. Firmware remains 0.2.0. No trusted Apple signing/notarization is claimed.
- Verify a native GUI upgrade and real rollback after an intentionally failed activation check on the supported unit; preserve its token, meals, journal and immutable flash hash, with local video recovered.
- Validate the published native app's stock restoration and first-install path on the previously paired test unit, including matching stock backups, fresh API credentials, unchanged meals/journal and original immutable flash. Factory-reset and unboxed onboarding remain untested.
- Document stock configuration changes causing a safe backup refusal, retry after the device settles, token changes after reinstalling, and reopening the Mac app when initial Local Network access has not taken effect.

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
