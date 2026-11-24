# Pet Feeder Local Firmware

Experimental local-control modification for the Anyka-based V330L-DU4L-VS camera feeder.

The goal is an authenticated local API, native RTSP video, and feeding schedules stored and executed by the feeder MCU. Scheduled feeding must keep working when Home Assistant, Wi-Fi, or Internet access is unavailable.

## Current evidence

- Root access was confirmed on one privately owned test device.
- Two complete 8 MiB flash reads matched byte for byte before experimentation.
- A RAM-only preload prototype delivered native RTSP HEVC video at 1920×1080 and 10 fps. Direct playback and go2rtc restreaming both decoded without errors while outbound Internet routes were blocked.
- The stock MCU returned its schedule table independently of Tuya cloud access.
- The authenticated HTTP API read, edited, verified, and restored a disabled MCU schedule with Internet blocked before application startup. Invalid tables and stale revisions were rejected.
- One one-portion request through the new API received an MCU acknowledgement. Repeating its operation ID did not send a second motor command. An acknowledgement does not prove that food physically reached the bowl.
- The stock Tuya LAN interface did not reliably recover after starting without Internet. The new API addresses the MCU directly and does not depend on Tuya LAN or tuya-local.
- No replacement firmware has been flashed. The test device was restored to its original executable and network routing after the initial experiments.
- The reversible persistent overlay subsequently passed a device reboot with WAN blocked before application startup: API, MCU schedule retention, clock acknowledgement, and authenticated RTSP decoding all passed. Immutable flash partitions still matched their original hash.
- With the complete camera application stopped for 25 seconds, the MCU emitted a scheduled-feeding record for a one-portion fixture while the API manual-command counter stayed unchanged. The original disabled schedule and actual wall time were restored. Physical delivery was not observed.

Battery-backed feeding has **not** been tested: the test device currently has no batteries. The RTSP prototype is not a complete local firmware release.

## Target

| Component | Observed value |
| --- | --- |
| Product family | V330L-DU4L-VS |
| SoC | Anyka AK39EV330, ARMv5TE |
| Stock application version | 68.00.09 |
| Stock application SHA-256 | `f499431d38ed3cb8a4607ee870f06461e14ccb9f6f6387137b0ded2f5191a499` |
| Linux | 4.4.192V2.1 |
| Flash | 8 MiB SPI NOR |

Other devices and firmware versions require separate ABI and hardware validation.

## Interface

- Explicit manual feeding with a bounded portion count and a persistent reservation journal covering the sixteen most recent operation IDs.
- Read, validate, update, and read back the MCU schedule table.
- Native RTSP streams for Home Assistant and Frigate.
- An MCU clock and schedule; Home Assistant synchronizes local wall time and configures meals, and the MCU executes their timers. Vendor clock/motor/schedule writes are filtered in the modified process.
- Reversible installation with a verified original-firmware backup and recovery path.

The companion integration is [ha-pet-feeder-local](https://github.com/e2equiel/ha-pet-feeder-local).

This is an overlay on the original application, **not a clean-room replacement of the vendor firmware**. The original camera encoder and MCU remain in use. More-specific unreachable routes block Internet traffic on the feeder while preserving its connected LAN. Kernel and root filesystem partitions are not modified.

See [API behavior](docs/local-api.md) for authentication, request semantics, and current limits.

## Repository boundaries

This repository contains original modification code, protocol documentation, and synthetic tests. Device flash dumps, vendor binaries, Wi-Fi settings, Tuya keys, API tokens, and home-camera recordings stay outside version control.

## References

- [Published root-access research](https://www.whid.ninja/blog/snhack-attack-how-hackers-could-turn-your-smart-pet-feeder-into-an-all-you-can-eat-buffet)
- [Anyka encoder ABI research](https://github.com/thxrben/anyka-rstp/blob/main/docs/libmpi_venc.md), cross-checked against the test device's own library
- [Tuya pet-camera offline scheduling architecture](https://developer.tuya.com/en/docs/iot-device-dev/pet-camera?id=Kdvgw71qj280g)
