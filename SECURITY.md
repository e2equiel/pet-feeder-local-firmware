# Security

The feeder is a trusted-LAN device. Its local HTTP API, RTSP and factory Telnet access are not encrypted. Do not forward these ports to the Internet. The project does not provide a remote cloud service.

Use GitHub's private vulnerability reporting for a security issue when available. For a public issue, describe the affected version and behavior without including credentials or exploitation of someone else's device. Never upload a device backup or the installer's private Home Assistant setup JSON.

The installer binds only to 127.0.0.1, checks Host and Origin, requires a per-run CSRF token, disables response caching and suppresses HTTP request logs. Firmware API requests need a device-specific random token; redirects are not followed. The known factory root password is not changed by this release, so LAN access to Telnet remains privileged.
