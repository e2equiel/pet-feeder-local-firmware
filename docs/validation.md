# Validation scope

Tests target one privately owned V330L-DU4L-VS, original application 68.00.09 and observed MCU revision 1-C6-XALCD.0.7. Other hardware/application/MCU variants have not been established as compatible.

## Prior hardware baseline (0.1 prototype)

Two complete 8 MiB factory flash reads matched. A persistent reversible overlay subsequently passed a full device reboot with Internet routing blocked before the retained camera application started. The authenticated API read, changed and exactly verified a disabled MCU schedule fixture, then restored the original table. Stale revisions and malformed rows were rejected. The immutable flash prefix still matched the original backup after reboot.

A one-portion API request and a later explicit HA Serve request were electronically acknowledged. Reusing the API request's operation ID emitted no second command. Selecting portions alone emitted no command. With the complete Linux camera application stopped for 25 seconds, the MCU emitted a scheduled-feeding serial record while the API manual counter remained unchanged. The original schedule and current clock were restored after the experiment.

Native main-stream HEVC video (1920×1080, 10 fps) decoded without errors directly and through local go2rtc. HA displayed still/live video; Frigate 0.18.3 decoded the shared local stream. No home video or credentials are included in this repository.

## Community installer (0.2)

The installer tests cover exact-profile refusal, foreign hook preservation, damaged bundles, binary transfer integrity, two matching complete backups, incomplete/differing backup refusal, private backup permissions, rollback preserving operation reservations, restore without a healthy API, recovery timer ordering, split Telnet negotiation, loopback Host/Origin/CSRF protections and disconnected demo operation. Native C tests run with AddressSanitizer and UndefinedBehaviorSanitizer for the bounded MCU codec, JSON parser and durable reservation journal. Cross-compilation rejects warnings and the actual target libc satisfies the module's dynamic imports.

The guided installer and integration card/editor were visually checked in a browser with synthetic disconnected data. Portable installers have no trusted publisher signature; source-installer fallback needs Python 3.10+ and no third-party Python packages.

The 0.2 installer also passed a real upgrade on the same unit: two full backups matched, the running process mapped the selected versioned module, the original meal rows and token were preserved, and the manual command counter stayed at zero. A new immutable-partition read matched the original baseline. The SSDP response and XML identity were checked against this target only; the shared local main stream produced 63 completely decoded frames after the upgrade. Leading non-keyframes were excluded when making the capture so that decoding started at a complete GOP.

The macOS ARM64 portable installer was built and smoke-tested locally: its embedded wizard and assets loaded without a separate Python installation. Windows, Linux and macOS portable builds are also checked by the release workflow; availability and checksums are shown in Releases.

## Remaining hardware checks

The earlier tests did not establish physical food delivery; later observations are recorded below. The test unit has no batteries or microSD. Battery-backed feeding, complete-power-loss clock retention, long-duration offline behavior, additional hardware variants, audio and the separate video substream remain unverified. A serial acknowledgement or scheduled-feeding record is not proof that food arrived in the bowl. The overlay retains the vendor's proprietary encoder and MCU firmware.

Automated software tests, on-device installation checks, successful camera decoding and physical feeding are distinct kinds of evidence. Do not read one as proof of the others.

## Installer 0.2.1 packaging update

A user downloaded the 0.2.0 macOS ZIP through a browser and macOS blocked Python and successive native extensions before the wizard could start. The original build-directory smoke test did not represent that Gatekeeper path. Installer 0.2.1 now creates a complete app bundle, preserves its resource links and signature envelope, and tests the extracted release archive. Ad-hoc bundle integrity and disconnected startup checks are distinct from Developer ID trust/notarization; the latter remains pending. See [macOS signing](macos-signing.md).

The source installer adds a double-clickable launcher for an existing trusted Python. The extracted macOS ARM64 app passed deep/strict signature integrity verification, disconnected startup, embedded-asset loading and clean shutdown. The source ZIP's launcher was checked with an existing Homebrew Python. The installer suite passes 27 tests, including startup with DNS unavailable and authenticated close behavior. The notarization operator rejects the ad-hoc build before an upload; its Apple submission path remains untested.

The installed firmware remains 0.2.0 and is not changed by these packaging updates. No further device or physical feeding experiment is needed or performed for this update.

## Native Mac installer (0.2.2)

The Swift port has 21 disconnected boundary tests covering private-address input, bundle integrity/path restrictions, unsupported profiles and foreign hooks, binary transfer limits, two matching full private backups, checked upload replacement, recovery ordering, failed activation, schedule mismatch rollback, existing token preservation, bounded HTTP parsing with no redirects, console length, real CRLF completion markers and split Telnet negotiation. The macOS package check extracts the ZIP, verifies its seal, checks for system-only dependencies and validates the embedded module and original app icon. A disconnected native window was checked through its connection/review screens; installation is disabled in that preview.

A native read-only probe on the same physical test unit verified the exact firmware profile and authenticated API, saved two complete matching flash reads and a private configuration archive, and confirmed unchanged meal rows. The immutable-partition hash matched the earlier hardware baseline. No install, restore or motor command was invoked by that probe. The native backup-folder picker was also checked visually with a private destination.

The native Mac app also passed a real upgrade through its connection, review, folder selection, confirmation, backup and completion screens. Both complete 8 MiB reads matched. The existing API token, three meal rows and durable operation journal were preserved, and the manual command counter remained zero. The selected module was mapped by the restarted camera process. A subsequent backup matched the original immutable-partition hash. Home Assistant reported the MCU online and three meals; Frigate delivered a freshly decoded JPEG with a positive camera frame rate.

Rollback was exercised on the same device with the production Swift core and a test-only Mac-side API verification callback that intentionally failed after activation. The standard double backups and checked upload ran first; the failure invoked the real device-side rollback script. The previous local installation recovered with its existing token and meal rows, and all armed recovery transactions were marked complete. The feeder's actual API and macOS security settings remained enabled throughout this experiment.

The published 0.2.2 ARM64 ZIP was then used for **Restore stock operation** through the native confirmation and completion screens. Before restoration, another two complete matching private backups were saved. Readback verified the original application fingerprint and immutable-partition hash, no local boot hook or enable marker, no application bind mount or loaded local module, no local API listener, and restored original Internet routing. The unit temporarily stopped responding before reconnecting at the same address.

The same downloaded app subsequently identified **First installation**. The first attempt refused activation because 158 bytes changed in the configuration partition between its complete flash reads. Both immutable snapshots still matched the original baseline. After three stable configuration reads, a normal retry produced two matching complete stock backups and completed installation with a newly generated API token. The current community integration API client authenticated those fresh credentials and read the three MCU meals. The meal table, durable journal and original immutable flash remained unchanged, manual command count stayed zero, the selected module was loaded, and the device's Internet block was reinstated. Frigate decoded the new authenticated local stream.

The HA prototype was subsequently upgraded to the published integration 0.2.1 through Marketplace, followed by one explicitly approved HA Core restart. Running diagnostics verified version 0.2.1. Its live **Reconfigure** flow rejected an incorrect token while retaining the working entry, then accepted the newly generated installer token and preserved the existing entry and restream option. The fresh token is now active in the feeder, HA and its local video source. The three MCU rows and durable journal remained unchanged; manual-command count stayed zero and Frigate decoded the authenticated stream at about 4 fps. Feeders 1 and 3 entry metadata and the protected Tuya registry configuration were compared before and after and remained unchanged. Only this project's old frontend resource URL was updated to the bundled card, whose served bytes matched the published source. Frigate was not restarted. See the [integration validation](https://github.com/e2equiel/ha-pet-feeder-local/blob/main/docs/validation.md) for the scope of these live checks.

Stock restoration deliberately retains inactive private history, Wi-Fi configuration and pairing records. This tests the first-install branch on a restored, previously paired unit; it is not a factory reset or an installation on an untouched, newly unboxed device. The firmware payload remains 0.2.0. Battery operation and complete-power-loss clock retention retain the limitations listed above; later physical meal observations are recorded below. This remains an experimental preview tested on one exact device profile.

## Owner-observed physical meals and weekdays

On the same exact device profile, the owner confirmed one manual one-portion delivery, a daily scheduled delivery, and two single-day diagnostic deliveries. Scheduled windows ran with WAN routing blocked and the whole Linux camera/control application paused for 25 seconds: the local API was unreachable and the manual-command counter did not increase. In the single-day trials the selected HA entry was also disabled.

A failed Tuesday raw mask `4` and successful Tuesday raw mask `16`, followed by successful raw mask `8` with the MCU date advanced to Wednesday, exposed the reverse weekday order in this UART profile. The original table/revision, actual wall clock and selected HA entry were restored. HA integration 0.4+ translates the masks; the firmware API and payload remain unchanged. Remaining individual weekdays follow the inferred bit-order model and were not physically exercised. No other feeder was actuated or modified.

These are short, observed trials on one unit. Battery-backed feeding, full-power-loss clock retention, long-duration offline behavior and other hardware variants remain unverified. The test unit still has no batteries or microSD.
