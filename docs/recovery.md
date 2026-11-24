# Recovery and troubleshooting

## Compatibility check fails

Check the IP address in your router and confirm that only the intended feeder is selected. Your computer and feeder must be on reachable LAN segments; guest Wi-Fi may isolate clients. The supported profile must already be paired to Wi-Fi. Telnet port 23 must be available with the supported factory root access. Incorrect credentials, unknown stock fingerprints, different partition layouts and another project's boot hook cause a refusal before installation. Do not force a check or erase another project's files.

## Backup fails or the two reads differ

Nothing is activated until both complete 8 MiB reads match. Let the feeder become idle, check Wi-Fi and free disk space on the computer, then rerun the wizard. Keep every completed backup private. Background flash writes can make two reads differ; that is a reason to retry the backup, not to skip verification. A full backup and configuration archive contain secrets.

## Installation cannot verify the new API

The installer restores its previous boot files, module selection and network routes, then restarts only the feeder's camera application. A separate on-device timer provides the same rollback if the PC connection is lost during activation. Existing operation reservations are never rolled back, which prevents reusing old reservations to trigger a second feed. The timer lives in RAM and needs power to execute. Leave power on for at least three minutes after a failed activation.

Recheck the device in the wizard. If an old overlay API is unhealthy, **Restore stock operation** still works without API authentication because it uses the verified factory Telnet route. Restore does not change the meal table. When there is no working overlay, no Restore button is shown.

If Wi-Fi or Telnet is entirely unavailable, software rollback over the network is unavailable too. Do not write a raw flash dump with guessed offsets. Keep your full backup; serial/SPI recovery requires hardware access and expertise and is outside this beginner installer. No software modification can promise zero risk of a failed device.

## Lost token

Find `home-assistant-setup.json` in the private backup folder on the installation computer. An upgrade preserves the existing token. Advanced owners can read `/mnt/config/pet-feeder-local/api.token` through their own root session. Never paste that file into a public issue. Use the integration's Reconfigure or reauthentication flow to update HA after an intentional token change.

## Change Wi-Fi or go back to Tuya

Use **Restore stock operation**, wait for the original app to reconnect, then use the manufacturer's normal Wi-Fi setup. The installer does not modify SSIDs, passwords, pairing records or MCU firmware. A factory reset is a vendor operation with its own effects; this project does not automate it. After Wi-Fi changes, recheck the new IP and install the overlay again if desired.

## Installed but HA cannot connect

Use the exact API address shown by the wizard, including `http://` and port `8080`. Check the private token, LAN reachability and power. The firmware blocks Internet routing but permits its directly connected LAN; routed VLAN access may need a deliberate network configuration beyond this installer. Do not forward HTTP, RTSP or Telnet ports to the Internet.

## Camera unavailable

Use the main stream with TCP and the private token. HEVC decoding is required. One upstream client is supported per feeder stream: use go2rtc for multiple consumers and enter its local restream URL in HA. A second direct client replaces the first. See [camera setup](camera.md).

## Reporting a problem

Report the model, original application version, overlay/installer version, OS, installation stage and sanitized error. Include HA's allowlisted integration diagnostics when relevant. Never upload flash/configuration backups, setup JSON, raw logs containing credentials, device identities or home video.
