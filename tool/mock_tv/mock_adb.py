#!/usr/bin/env python3
"""A mock Android device speaking the ADB protocol over TCP ("network debugging").

Used by the Dart integration tests for the app's ADB channel and validated
against the reference client `adb_shell` (validate_mock_adb.py). It behaves
like a TV with network debugging turned on:

* CNXN -> AUTH token; signatures from known keys are accepted.
* An unknown key is offered with AUTH RSAPUBLICKEY; the "TV" then shows its
  "Allow debugging?" prompt. Here the answer is automatic: accept after
  --approve-delay seconds, or never with --reject.
* OPEN "shell:<cmd>" runs nothing; it reports the command as a JSON event and
  answers like `input keyevent` does (no output, then close).

Events on stdout, one JSON object per line:
  {"event": "ready", "port": 41234}
  {"event": "auth_prompt", "key_comment": "haam-remote@phone"}
  {"event": "connected", "known_key": true}
  {"event": "shell", "command": "input keyevent 183"}

Dependencies: cryptography.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import secrets
import socket
import struct
import sys
import threading
import time

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa, utils


def cmd(name: bytes) -> int:
    return struct.unpack("<I", name)[0]


CNXN, AUTH, OPEN, OKAY, CLSE, WRTE = (cmd(n) for n in (b"CNXN", b"AUTH", b"OPEN", b"OKAY", b"CLSE", b"WRTE"))
AUTH_TOKEN, AUTH_SIGNATURE, AUTH_RSAPUBLICKEY = 1, 2, 3
VERSION = 0x01000000
MAX_DATA = 256 * 1024

_lock = threading.Lock()


def emit(event: str, **data: object) -> None:
    with _lock:
        sys.stdout.write(json.dumps({"event": event, **data}) + "\n")
        sys.stdout.flush()


# Network interfaces of the simulated TV. The Wi-Fi MAC differs from the one
# in the remote service's certificate, as it can on real TVs.
INTERFACES = "1: lo: <LOOPBACK,UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT\\    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00\n" \
    "2: eth0: <BROADCAST,MULTICAST> mtu 1500 qdisc mq state DOWN mode DEFAULT\\    link/ether aa:bb:cc:dd:ee:0f brd ff:ff:ff:ff:ff:ff\n" \
    "3: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DORMANT\\    link/ether aa:bb:cc:dd:ee:10 brd ff:ff:ff:ff:ff:ff\n" \
    "4: p2p0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN mode DEFAULT\\    link/ether ae:bb:cc:dd:ee:10 brd ff:ff:ff:ff:ff:ff\n"


HELPER = "com.haam.keepawake"
HELPER_SERVICE = f"{HELPER}/.KeepAwakeService"


def decode_android_pubkey(text: bytes) -> rsa.RSAPublicKey:
    """Parse Android's mincrypt RSAPublicKey struct (base64, then ' comment')."""
    b64 = text.split(b"\0")[0].split(b" ")[0]
    raw = base64.b64decode(b64)
    words, n0inv = struct.unpack_from("<II", raw, 0)
    size = words * 4
    n = int.from_bytes(raw[8 : 8 + size], "little")
    rr = int.from_bytes(raw[8 + size : 8 + 2 * size], "little")
    (e,) = struct.unpack_from("<I", raw, 8 + 2 * size)
    if len(raw) != 8 + 2 * size + 4:
        raise ValueError("bad key length")
    if (n * n0inv) % (1 << 32) != (1 << 32) - 1:
        raise ValueError("bad n0inv")
    if rr != pow(1 << (size * 8), 2, n):
        raise ValueError("bad rr")
    return rsa.RSAPublicNumbers(e, n).public_key()


class Conn:
    def __init__(self, sock: socket.socket) -> None:
        self.sock = sock
        self.buf = b""

    def send(self, command: int, arg0: int, arg1: int, data: bytes = b"") -> None:
        header = struct.pack("<6I", command, arg0, arg1, len(data), sum(data) & 0xFFFFFFFF, command ^ 0xFFFFFFFF)
        self.sock.sendall(header + data)

    def _read(self, n: int) -> bytes | None:
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                return None
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def recv(self):
        header = self._read(24)
        if header is None:
            return None
        command, arg0, arg1, length, checksum, magic = struct.unpack("<6I", header)
        if magic != command ^ 0xFFFFFFFF:
            raise ValueError("bad magic")
        data = self._read(length) if length else b""
        if data is None:
            return None
        if checksum and checksum != (sum(data) & 0xFFFFFFFF):
            raise ValueError("bad checksum")
        return command, arg0, arg1, data


class MockAdb:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.known: list[rsa.RSAPublicKey] = []
        self.lock = threading.Lock()
        # Simulated package manager and services, enough for the TV helper.
        self.installed: set[str] = set()
        self.running: set[str] = set()

    def shell_output(self, command: str) -> bytes:
        """What the simulated device prints for a shell command (most print nothing)."""
        out = ""
        if command.startswith("ip -o link"):
            # Like the real shell: the `ip` listing, then the sysfs fallback lines.
            out = INTERFACES + "wlan0 aa:bb:cc:dd:ee:10\neth0 aa:bb:cc:dd:ee:0f\n"
        with self.lock:
            if f"pm list packages {HELPER}" in command and HELPER in self.installed:
                out += f"package:{HELPER}\n"
            if "grep -c" in command and "haam:keepawake" in command:
                out += "1\n" if HELPER in self.running else "0\n"
            if f"am start-foreground-service -n {HELPER_SERVICE}" in command:
                if HELPER in self.installed:
                    self.running.add(HELPER)
                    out += f"Starting service: Intent {{ cmp={HELPER_SERVICE} }}\n"
                else:
                    out += "Error: Not found; no service started.\n"
            if f"dumpsys deviceidle whitelist +{HELPER}" in command:
                out += f"Added: {HELPER}\n"
            if f"pm uninstall {HELPER}" in command:
                if HELPER in self.installed:
                    self.installed.discard(HELPER)
                    self.running.discard(HELPER)
                    out += "Success\n"
                else:
                    out += "Failure [DELETE_FAILED_INTERNAL_ERROR]\n"
        return out.encode()

    def install(self, apk: bytes) -> bytes:
        """`cmd package install`: accepts anything shaped like an APK (a zip)."""
        emit("install", size=len(apk), sha256=hashlib.sha256(apk).hexdigest())
        if not apk.startswith(b"PK\x03\x04"):
            return b"Failure [INSTALL_PARSE_FAILED_NOT_APK: not a zip]\n"
        with self.lock:
            self.installed.add(HELPER)
            self.running.discard(HELPER)  # updating an app stops it
        return b"Success\n"

    def verify(self, token: bytes, signature: bytes) -> bool:
        with self.lock:
            keys = list(self.known)
        for key in keys:
            try:
                key.verify(signature, token, padding.PKCS1v15(), utils.Prehashed(hashes.SHA1()))
                return True
            except InvalidSignature:
                continue
        return False

    def serve(self, sock: socket.socket) -> None:
        conn = Conn(sock)
        token = secrets.token_bytes(20)
        connected = False
        local_ids = 0
        # Streams that take input (exec:cmd package install -S N), by our id.
        uploads: dict[int, dict] = {}
        try:
            while True:
                msg = conn.recv()
                if msg is None:
                    return
                command, arg0, arg1, data = msg
                if command == CNXN:
                    token = secrets.token_bytes(20)
                    conn.send(AUTH, AUTH_TOKEN, 0, token)
                elif command == AUTH and arg0 == AUTH_SIGNATURE:
                    if self.verify(token, data):
                        connected = True
                        emit("connected", known_key=True)
                        conn.send(CNXN, VERSION, self.args.max_payload, b"device::ro.product.name=R4;ro.product.model=R4;\0")
                    else:
                        token = secrets.token_bytes(20)
                        conn.send(AUTH, AUTH_TOKEN, 0, token)
                elif command == AUTH and arg0 == AUTH_RSAPUBLICKEY:
                    key = decode_android_pubkey(data)
                    comment = data.rstrip(b"\0").split(b" ", 1)[1].decode() if b" " in data else ""
                    emit("auth_prompt", key_comment=comment)
                    if self.args.reject:
                        continue  # the prompt is never answered
                    time.sleep(self.args.approve_delay)
                    with self.lock:
                        self.known.append(key)
                    connected = True
                    emit("connected", known_key=False)
                    conn.send(CNXN, VERSION, self.args.max_payload, b"device::ro.product.name=R4;ro.product.model=R4;\0")
                elif command == OPEN and connected:
                    local_ids += 1
                    remote_id = arg0
                    destination = data.rstrip(b"\0").decode()
                    if destination.startswith("exec:cmd package install"):
                        parts = destination.split()
                        size = int(parts[parts.index("-S") + 1]) if "-S" in parts else -1
                        emit("exec", command=destination[len("exec:"):])
                        uploads[local_ids] = {"remote": remote_id, "size": size, "data": bytearray()}
                        conn.send(OKAY, local_ids, remote_id)
                        continue
                    if not destination.startswith("shell:"):
                        conn.send(CLSE, 0, remote_id)  # like adbd for a service it does not offer
                        continue
                    command_line = destination[len("shell:"):]
                    emit("shell", command=command_line)
                    conn.send(OKAY, local_ids, remote_id)
                    output = self.shell_output(command_line)
                    if output:
                        conn.send(WRTE, local_ids, remote_id, output)
                    conn.send(CLSE, local_ids, remote_id)
                elif command == WRTE and arg1 in uploads:
                    upload = uploads[arg1]
                    if len(data) > self.args.max_payload:
                        emit("error", detail=f"WRTE of {len(data)} bytes exceeds max payload")
                        return
                    upload["data"] += data
                    conn.send(OKAY, arg1, arg0)
                    if len(upload["data"]) >= upload["size"]:
                        del uploads[arg1]
                        conn.send(WRTE, arg1, arg0, self.install(bytes(upload["data"])))
                        conn.send(CLSE, arg1, arg0)
                elif command in (OKAY, CLSE, WRTE):
                    if command == WRTE:
                        conn.send(OKAY, arg1, arg0)
                else:
                    emit("unexpected", command=command)
        except (OSError, ValueError) as exc:
            emit("error", detail=str(exc))
        finally:
            sock.close()

    def run(self) -> None:
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", self.args.port))
        server.listen(8)
        emit("ready", port=server.getsockname()[1])

        def accept() -> None:
            while True:
                sock, _ = server.accept()
                threading.Thread(target=self.serve, args=(sock,), daemon=True).start()

        threading.Thread(target=accept, daemon=True).start()
        for _ in sys.stdin:  # exit when the test harness closes stdin
            pass
        os._exit(0)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=5555)
    parser.add_argument("--approve-delay", type=float, default=0.3)
    parser.add_argument("--reject", action="store_true")
    parser.add_argument("--max-payload", type=int, default=MAX_DATA, help="max payload announced in CNXN")
    MockAdb(parser.parse_args()).run()


if __name__ == "__main__":
    main()
