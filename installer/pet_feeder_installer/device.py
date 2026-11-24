"""Back up and modify one explicitly selected feeder without flashing partitions."""

from __future__ import annotations

import base64
from collections.abc import Callable
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import secrets
import shlex
import time
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener

from .bundle import Bundle, FLASH_SIZE, IMMUTABLE_SIZE, PARTITION_SIZES, STOCK_SHA256
from .telnet import DeviceError, Telnet

STATE = "/mnt/config/pet-feeder-local"
HOOK = "/mnt/config/tmp_test.sh"
HOOK_MARKER = "PET_FEEDER_LOCAL_BOOT_HOOK"
Progress = Callable[[str, str], None]


class NoRedirects(HTTPRedirectHandler):
    """Never send a device token to a redirected location."""

    def redirect_request(self, *_: object, **__: object) -> None:
        return None


def device_api(host: str, token: str, path: str) -> dict[str, object]:
    request = Request(
        f"http://{host}:8080/api/v1/{path}",
        headers={"Authorization": "Bearer " + token},
    )
    with build_opener(NoRedirects, ProxyHandler({})).open(request, timeout=5) as response:
        payload = response.read(8193)
    if len(payload) > 8192:
        raise DeviceError("The local API response is too large.")
    result = json.loads(payload)
    if not isinstance(result, dict):
        raise DeviceError("The device returned an invalid local API response.")
    return result


class Installer:
    """Installing and restoring never send a feeding or schedule-write command."""

    def __init__(self, transport: Telnet, bundle: Bundle, progress: Progress) -> None:
        self.transport = transport
        self.bundle = bundle
        self.progress = progress
        self.details: dict[str, object] | None = None
        self.token = ""
        self.previous_schedule: object = None

    def read(self, command: str, *, maximum: int, timeout: float = 180) -> bytes:
        marker = "PFL_DATA_" + secrets.token_hex(12)
        output = self.transport.run(
            f"printf '\\n{marker}_BEGIN\\n'\n{command} | busybox base64\n"
            f"printf '\\n{marker}_END\\n'",
            timeout=timeout,
            limit=maximum * 2 + 65536,
        )
        try:
            encoded = output.split("\n" + marker + "_BEGIN\n", 1)[1].split(
                "\n" + marker + "_END\n", 1
            )[0]
            result = base64.b64decode("".join(encoded.split()), validate=True)
        except (IndexError, ValueError) as error:
            raise DeviceError("The backup transfer was interrupted. Retry before installing.") from error
        if len(result) > maximum:
            raise DeviceError("The device returned an unexpectedly large file.")
        return result

    def upload(self, path: str, payload: bytes) -> None:
        """Push small base64 chunks over the existing connection; no firewall prompt."""
        quoted = shlex.quote(path)
        temporary = shlex.quote(path + ".new-" + secrets.token_hex(8))
        self.transport.run(f": > {temporary}\nchmod 600 {temporary}")
        for cursor in range(0, len(payload), 96):
            if len(payload) > 4096 and cursor % (96 * 25) == 0:
                self.progress("installing", f"Uploading the local camera and control service… {cursor * 100 // len(payload)}%")
            encoded = base64.b64encode(payload[cursor : cursor + 96]).decode()
            self.transport.run(f"printf '%s' '{encoded}' | busybox base64 -d >> {temporary}")
        digest = hashlib.sha256(payload).hexdigest()
        result = self.transport.run(f"busybox sha256sum {temporary}")
        if not re.search(rf"(?m)^{digest}\s", result):
            raise DeviceError("An uploaded file failed verification. Activation was not attempted.")
        self.transport.run(f"mv -f {temporary} {quoted}")

    def inspect(self, *, require_api: bool = True) -> dict[str, object]:
        self.progress("checking", "Checking this feeder's exact firmware and flash layout…")
        applets = self.transport.run("busybox --list")
        if not {"base64", "sha256sum", "tar", "dd"}.issubset(set(applets.split())):
            raise DeviceError("This firmware lacks required backup tools. This device is not supported.")
        partitions = self.transport.run("cat /proc/mtd")
        sizes = {int(index): int(size, 16) for index, size in re.findall(r"mtd(\d+):\s+([0-9a-f]+)", partitions)}
        if tuple(sizes.get(index) for index in range(7)) != PARTITION_SIZES or len(sizes) != 7:
            raise DeviceError("The flash layout does not match the supported device. Nothing was installed.")
        hook = self.read(f"test ! -f {HOOK} || cat {HOOK}", maximum=16384).decode(errors="replace")
        if hook and HOOK_MARKER not in hook:
            raise DeviceError("This feeder has another boot modification. The installer will not overwrite it.")
        mounted = " /usr/sbin/ak_tuya_ipc " in self.transport.run("cat /proc/mounts")
        application = "/run/pet-feeder-local/ak_tuya_ipc" if mounted and hook else "/usr/sbin/ak_tuya_ipc"
        output = self.transport.run(f"busybox sha256sum {application}")
        if not re.search(rf"(?m)^{STOCK_SHA256}\s", output):
            raise DeviceError("This stock firmware version is not supported. Do not force installation.")
        mac = self.read("cat /sys/class/net/wlan0/address", maximum=128).decode().strip().lower()
        if not re.fullmatch(r"(?:[0-9a-f]{2}:){5}[0-9a-f]{2}", mac):
            raise DeviceError("Could not read a reliable device identity.")
        if hook and require_api:
            token = self.read(f"cat {STATE}/api.token", maximum=128).decode().strip()
            if re.fullmatch(r"[A-Za-z0-9_-]{32,96}", token):
                self.token = token
                try:
                    self.previous_schedule = device_api(self.transport.host, token, "schedules")["meals"]
                except (OSError, ValueError, KeyError):
                    raise DeviceError("The existing local installation is not healthy. Use Restore before upgrading.") from None
            else:
                raise DeviceError("The existing API token is missing or invalid. Use Restore before reinstalling.")
        self.details = {"model": "V330L-DU4L-VS", "stock_version": "68.00.09", "identity": mac,
                        "stock_application_sha256": STOCK_SHA256, "upgrade": bool(hook),
                        "version_to_install": self.bundle.version}
        return self.details

    def backup(self, destination: Path) -> Path:
        if self.details is None:
            self.inspect()
        destination.mkdir(parents=True, exist_ok=True, mode=0o700)
        suffix = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + secrets.token_hex(4)
        directory = destination / ("feeder-" + suffix)
        directory.mkdir(mode=0o700)
        checksums: dict[str, str] = {}
        readings: list[bytes] = []
        for index in (1, 2):
            self.progress("backup", f"Reading backup {index} of 2. Keep the feeder powered on…")
            data = self.read("cat " + " ".join(f"/dev/mtd{i}" for i in range(7)), maximum=FLASH_SIZE)
            if len(data) != FLASH_SIZE:
                raise DeviceError("A complete flash backup could not be read. Nothing was installed.")
            path = directory / f"flash-read-{index}.bin"
            path.write_bytes(data)
            path.chmod(0o600)
            checksums[path.name] = hashlib.sha256(data).hexdigest()
            readings.append(data)
        if readings[0] != readings[1]:
            raise DeviceError("The two flash backups differ. Wait until the feeder is idle, then retry.")
        config = self.read("tar -C /mnt/config -cf - .", maximum=4 * 1024 * 1024)
        if len(config) < 1024:
            raise DeviceError("The configuration backup is incomplete. Nothing was installed.")
        (directory / "private-configuration.tar").write_bytes(config)
        (directory / "private-configuration.tar").chmod(0o600)
        checksums["private-configuration.tar"] = hashlib.sha256(config).hexdigest()
        metadata = {"device": self.details, "files": checksums,
                    "immutable_flash_sha256": hashlib.sha256(readings[0][:IMMUTABLE_SIZE]).hexdigest(),
                    "warning": "Private: contains Wi-Fi and device credentials. Never upload this directory."}
        (directory / "backup.json").write_text(json.dumps(metadata, indent=2) + "\n")
        (directory / "backup.json").chmod(0o600)
        (directory / "KEEP_PRIVATE.txt").write_text(
            "These backups contain credentials. Keep them offline. Never attach them to a GitHub issue.\n"
            "The installer rollback restores its own overlay files; raw flash restoration requires hardware expertise.\n"
        )
        return directory

    def install(self, destination: Path) -> dict[str, object]:
        details = self.inspect()
        backup = self.backup(destination)
        self.progress("installing", "Backups match. Uploading and checking the local firmware overlay…")
        transaction = "/run/pet-feeder-install-" + secrets.token_hex(12)
        release = f"{STATE}/releases/{self.bundle.module_sha256}"
        self.transport.run(f"mkdir -p {STATE} {STATE}/releases {release} {transaction}\nchmod 700 {STATE} {transaction}")
        self.transport.run(
            f"for name in active boot.sh; do test ! -f {STATE}/$name || cp {STATE}/$name {transaction}/$name; done\n"
            f"test ! -f {HOOK} || cp {HOOK} {transaction}/hook\n"
            f"test ! -f {STATE}/enabled || touch {transaction}/was-enabled\n"
            f"test ! -f {STATE}/feeding.enabled || touch {transaction}/was-feeding-enabled"
        )
        rollback = self._rollback_script(transaction)
        self.upload(transaction + "/rollback.sh", rollback.encode())
        activated = False
        try:
            self.upload(release + "/pf_local.so", (self.bundle.directory / "pf_local.so").read_bytes())
            self.upload(release + "/module.sha256", (self.bundle.module_sha256 + "  pf_local.so\n").encode())
            self.transport.run(f"cd {release} && busybox sha256sum -c module.sha256\n"
                               f"LD_BIND_NOW=1 LD_PRELOAD={release}/pf_local.so /bin/true")
            # Arm recovery before replacing any boot files. The old module is
            # never truncated, and the previous journal is never rolled back.
            self.transport.run(
                f"(trap '' HUP; sleep 180; /bin/sh {transaction}/rollback.sh) > {transaction}/rollback.log 2>&1 &"
            )
            self.upload(STATE + "/boot.sh", (self.bundle.directory / "boot.sh").read_bytes())
            self.upload(STATE + "/uninstall.sh", (self.bundle.directory / "uninstall.sh").read_bytes())
            if not self.token:
                self.token = secrets.token_hex(32)
                self.upload(STATE + "/api.token", (self.token + "\n").encode())
            self.upload(STATE + "/active", (self.bundle.module_sha256 + "\n").encode())
            self.upload(HOOK, ("#!/bin/sh\n# " + HOOK_MARKER + "\n/bin/sh " + STATE
                               + "/boot.sh > /run/pet-feeder-local-boot.log 2>&1 || true\n").encode())
            self.transport.run(
                f"chmod 600 {STATE}/api.token\nchmod 700 {HOOK} {STATE}/boot.sh {STATE}/uninstall.sh\n"
                f"touch {STATE}/enabled {STATE}/feeding.enabled\nsync"
            )
            activated = True
            self.progress("restarting", "Restarting only this feeder's camera application…")
            self.transport.run(
                "if grep -q ' /usr/sbin/ak_tuya_ipc ' /proc/mounts; then umount /usr/sbin/ak_tuya_ipc; fi\n"
                f"/bin/sh {STATE}/boot.sh && kill -TERM $(pidof ak_tuya_ipc)"
            )
            deadline = time.monotonic() + 75
            while time.monotonic() < deadline:
                try:
                    # A version string alone cannot distinguish two development
                    # builds. Verify the running process mapped this exact release.
                    try:
                        self.transport.run(f"pid=$(pidof ak_tuya_ipc); test -n \"$pid\"; grep -F '{release}/pf_local.so' /proc/$pid/maps")
                    except DeviceError:
                        time.sleep(1)
                        continue
                    info = device_api(self.transport.host, self.token, "info")
                    if info.get("version") == self.bundle.version and info.get("id") == details["identity"]:
                        schedule = device_api(self.transport.host, self.token, "schedules")
                        if self.previous_schedule is not None and schedule.get("meals") != self.previous_schedule:
                            raise DeviceError("Schedule verification failed. Restoring the previous installation.")
                        break
                except (HTTPError, URLError, TimeoutError, ConnectionError, OSError, ValueError):
                    pass
                time.sleep(1)
            else:
                raise DeviceError("The local API did not start. Restoring the previous installation.")
            self.transport.run(f"touch {transaction}/committed\nsync")
            result = {"model": details["model"], "version": self.bundle.version,
                      "api_address": f"http://{self.transport.host}:8080", "token": self.token,
                      "backup_directory": str(backup), "scheduled_meals": len(schedule.get("meals", [])),
                      "rtsp_address": f"rtsp://feeder:TOKEN@{self.transport.host}:8555/live"}
            private_result = backup / "home-assistant-setup.json"
            private_result.write_text(json.dumps(result, indent=2) + "\n")
            private_result.chmod(0o600)
            self.progress("complete", "Installed. Keep your backups private, then connect Pet Feeder Local in Home Assistant.")
            return result
        except BaseException:
            if activated:
                self.progress("restoring", "Verification failed. Restoring the previous installation…")
            try:
                self.transport.run(f"/bin/sh {transaction}/rollback.sh")
            except (OSError, DeviceError):
                # A device-side timer also restores the previous state if the PC disconnects.
                pass
            raise

    @staticmethod
    def _rollback_script(transaction: str) -> str:
        return f"""#!/bin/sh
test ! -f {transaction}/committed || exit 0
if test -f {transaction}/active; then
    cp {transaction}/active {STATE}/active.rollback && mv -f {STATE}/active.rollback {STATE}/active
else
    rm -f {STATE}/active
fi
if test -f {transaction}/boot.sh; then cp {transaction}/boot.sh {STATE}/boot.sh; fi
if test -f {transaction}/hook; then cp {transaction}/hook {HOOK}; chmod 700 {HOOK}; else rm -f {HOOK}; fi
if test ! -f {transaction}/was-feeding-enabled; then rm -f {STATE}/feeding.enabled; fi
if grep -q ' /usr/sbin/ak_tuya_ipc ' /proc/mounts; then umount /usr/sbin/ak_tuya_ipc; fi
if test -f {transaction}/was-enabled; then
    /bin/sh {STATE}/boot.sh
else
    rm -f {STATE}/enabled
    busybox ip route del unreachable 0.0.0.0/1 2>/dev/null || true
    busybox ip route del unreachable 128.0.0.0/1 2>/dev/null || true
fi
pid=$(pidof ak_tuya_ipc || true)
test -z "$pid" || kill -TERM $pid
touch {transaction}/committed
sync
"""

    def restore(self) -> None:
        self.inspect(require_api=False)
        self.progress("restoring", "Disabling this overlay and restoring the stock boot path…")
        self.transport.run(f"test -f {STATE}/uninstall.sh && /bin/sh {STATE}/uninstall.sh")
        self.progress("complete", "The stock application and network routing have been restored. Meal schedules were not changed.")
