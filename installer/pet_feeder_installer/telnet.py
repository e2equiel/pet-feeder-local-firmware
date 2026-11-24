"""A bounded Telnet transport; Python 3.13+ does not include telnetlib."""

from __future__ import annotations

import ipaddress
import base64
import re
import secrets
import socket
import time


class DeviceError(Exception):
    """A user-facing installation error without credentials or command output."""


def local_address(value: str) -> str:
    """Accept exactly one RFC 1918 IPv4 address, never a subnet or public host."""
    try:
        address = ipaddress.IPv4Address(value.strip())
    except ipaddress.AddressValueError as error:
        raise DeviceError("Enter the feeder's private IPv4 address, for example 192.168.1.123.") from error
    networks = ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
    if not any(address in ipaddress.IPv4Network(network) for network in networks):
        raise DeviceError("Only a private LAN address is accepted. The installer never scans the network.")
    return str(address)


class Telnet:
    """One explicit target, with negotiation and bounded command responses."""

    def __init__(self, host: str, password: str, *, port: int = 23) -> None:
        self.host = local_address(host)
        if not password or any(character in password for character in "\r\n\x00"):
            raise DeviceError("Enter a valid root password.")
        self.socket = socket.create_connection((self.host, port), timeout=5)
        self.socket.settimeout(0.4)
        self._partial = b""
        try:
            self._until(rb"login:\s*$", 10)
            self.socket.sendall(b"root\r\n")
            self._until(rb"Password:\s*$", 5)
            self.socket.sendall(password.encode() + b"\r\n")
            result = self._until(rb"(?:[#\$] ?|Login incorrect)", 8)
            if b"Login incorrect" in result:
                raise DeviceError("The feeder rejected the root password. Nothing was installed.")
        except BaseException:
            self.socket.close()
            raise

    def _clean(self, data: bytes) -> bytes:
        data = self._partial + data
        self._partial = b""
        output = bytearray()
        cursor = 0
        while cursor < len(data):
            if data[cursor] != 255:
                output.append(data[cursor])
                cursor += 1
                continue
            if cursor + 1 >= len(data):
                self._partial = data[cursor:]
                break
            command = data[cursor + 1]
            if command == 255:
                output.append(255)
                cursor += 2
            elif command in (251, 252, 253, 254):
                if cursor + 2 >= len(data):
                    self._partial = data[cursor:]
                    break
                if command == 253:
                    self.socket.sendall(bytes((255, 252, data[cursor + 2])))
                elif command == 251:
                    self.socket.sendall(bytes((255, 254, data[cursor + 2])))
                cursor += 3
            elif command == 250:
                end = data.find(b"\xff\xf0", cursor + 2)
                if end < 0:
                    self._partial = data[cursor:]
                    break
                cursor = end + 2
            else:
                cursor += 2
        return bytes(output).replace(b"\r\x00", b"\r")

    def _until(self, pattern: bytes, timeout: float, limit: int = 128 * 1024) -> bytes:
        deadline = time.monotonic() + timeout
        output = bytearray()
        while time.monotonic() < deadline:
            try:
                data = self.socket.recv(65536)
            except socket.timeout:
                continue
            if not data:
                raise DeviceError("The connection to the feeder closed. Check its power and address.")
            output.extend(self._clean(data))
            if len(output) > limit:
                raise DeviceError("The feeder returned more data than expected. Installation stopped.")
            if re.search(pattern, output[-512:]):
                return bytes(output)
        raise DeviceError("The feeder did not respond in time. Check its power and Wi-Fi connection.")

    def run(self, command: str, *, timeout: float = 20, limit: int = 128 * 1024) -> str:
        marker = "PFL_DONE_" + secrets.token_hex(12)
        # A single interactive line avoids shell prompts and echoed commands
        # being interleaved with binary-backup base64 output.
        encoded = base64.b64encode(command.encode()).decode()
        envelope = (f"printf '%s' '{encoded}' | busybox base64 -d | /bin/sh -e; "
                    f"pfl_code=$?; printf '\\n{marker}%s\\n' \"$pfl_code\"\n")
        if len(envelope.encode()) > 1000:
            raise DeviceError("An installer command exceeds the supported console limit. Activation was stopped.")
        self.socket.sendall(envelope.encode())
        output = self._until(rb"\r?\n" + marker.encode() + rb"\d+\r?\n", timeout, limit)
        match = re.search(marker.encode() + rb"(\d+)\r?\n", output)
        if match is None or int(match[1]) != 0:
            raise DeviceError("A device check failed. Installation stopped; no raw flash is written.")
        return output.decode(errors="replace").replace("\r", "")

    def close(self) -> None:
        try:
            self.socket.sendall(b"exit\n")
        except OSError:
            pass
        self.socket.close()

    def __enter__(self) -> Telnet:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()
