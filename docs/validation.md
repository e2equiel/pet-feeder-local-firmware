# Validation scope

Tests target one privately owned V330L-DU4L-VS, original application 68.00.09 and observed MCU revision 1-C6-XALCD.0.7. Other hardware/application/MCU variants have not been established as compatible.

## Prior hardware baseline (0.1 prototype)

Two complete 8 MiB factory flash reads matched. A persistent reversible overlay subsequently passed a full device reboot with Internet routing blocked before the retained camera application started. The authenticated API read, changed and exactly verified a disabled MCU schedule fixture, then restored the original table. Stale revisions and malformed rows were rejected. The immutable flash prefix still matched the original backup after reboot.

A one-portion API request and a later explicit HA Serve request were electronically acknowledged. Reusing the API request's operation ID emitted no second command. Selecting portions alone emitted no command. With the complete Linux camera application stopped for 25 seconds, the MCU emitted a scheduled-feeding serial record while the API manual counter remained unchanged. The original schedule and current clock were restored after the experiment.

Native main-stream HEVC video (1920×1080, 10 fps) decoded without errors directly and through local go2rtc. HA displayed still/live video; Frigate 0.18.3 decoded the shared local stream. No home video or credentials are included in this repository.

## Community installer (0.2)

The installer tests cover exact-profile refusal, foreign hook preservation, damaged bundles, binary transfer integrity, two matching complete backups, incomplete/differing backup refusal, private backup permissions, rollback preserving operation reservations, restore without a healthy API, recovery timer ordering, split Telnet negotiation, loopback Host/Origin/CSRF protections and disconnected demo operation. Native C tests run with AddressSanitizer and UndefinedBehaviorSanitizer for the bounded MCU codec, JSON parser and durable reservation journal. Cross-compilation rejects warnings and the actual target libc satisfies the module's dynamic imports.

The guided installer and integration card/editor were visually checked in a browser with synthetic disconnected data. Portable installers are unsigned; source-installer fallback needs Python 3.10+ and no third-party Python packages.

The 0.2 installer also passed a real upgrade on the same unit: two full backups matched, the running process mapped the selected versioned module, the original meal rows and token were preserved, and the manual command counter stayed at zero. A new immutable-partition read matched the original baseline. The SSDP response and XML identity were checked against this target only; the shared local main stream produced 63 completely decoded frames after the upgrade. Leading non-keyframes were excluded when making the capture so that decoding started at a complete GOP.

The macOS ARM64 portable installer was built and smoke-tested locally: its embedded wizard and assets loaded without a separate Python installation. Windows, Linux and macOS portable builds are also checked by the release workflow; availability and checksums are shown in Releases.

## Remaining hardware checks

Physical food delivery has not been observed. The test unit has no batteries or microSD. Battery-backed feeding, complete-power-loss clock retention, long-duration offline behavior, additional hardware variants, audio and the separate video substream remain unverified. A serial acknowledgement or scheduled-feeding record is not proof that food arrived in the bowl. The overlay retains the vendor's proprietary encoder and MCU firmware.

Automated software tests, on-device installation checks, successful camera decoding and physical feeding are distinct kinds of evidence. Do not read one as proof of the others.
