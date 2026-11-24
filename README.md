# Pet Feeder Local Firmware

Experimental local-control modification for the Anyka-based V330L-DU4L-VS camera feeder.

The goal is an authenticated local API, native RTSP video, and feeding schedules stored and executed by the feeder MCU. Scheduled feeding must keep working when Home Assistant, Wi-Fi, or Internet access is unavailable.

## Current evidence

- Root access was confirmed on one privately owned test device.
- Two complete 8 MiB flash reads matched byte for byte before experimentation.
- A RAM-only preload prototype delivered native RTSP HEVC video at 1920×1080 and 10 fps. Direct playback and go2rtc restreaming both decoded without errors while outbound Internet routes were blocked.
- The stock MCU returned its schedule table independently of Tuya cloud access.
- The stock Tuya LAN interface did not reliably recover after starting without Internet. The new control API will therefore address the MCU directly rather than depend on Tuya LAN or tuya-local.
- No replacement firmware has been flashed. The test device was restored to its original executable and network routing after the initial experiments.

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

## Planned interface

- Explicit manual feeding with a bounded portion count and an idempotent operation ID.
- Read, validate, update, and read back the MCU schedule table.
- Native RTSP streams for Home Assistant and Frigate.
- An independent MCU clock and schedule; Home Assistant will configure meals, not execute their timers.
- Reversible installation with a verified original-firmware backup and recovery path.

The companion integration is [ha-pet-feeder-local](https://github.com/e2equiel/ha-pet-feeder-local).

## Repository boundaries

This repository contains original modification code, protocol documentation, and synthetic tests. Device flash dumps, vendor binaries, Wi-Fi settings, Tuya keys, API tokens, and home-camera recordings stay outside version control.

## References

- [Published root-access research](https://www.whid.ninja/blog/snhack-attack-how-hackers-could-turn-your-smart-pet-feeder-into-an-all-you-can-eat-buffet)
- [Anyka encoder ABI research](https://github.com/thxrben/anyka-rstp/blob/main/docs/libmpi_venc.md), cross-checked against the test device's own library
- [Tuya pet-camera offline scheduling architecture](https://developer.tuya.com/en/docs/iot-device-dev/pet-camera?id=Kdvgw71qj280g)
