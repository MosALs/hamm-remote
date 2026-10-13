#!/usr/bin/env python3
"""Validate mock_tv.py against the reference client `androidtvremote2`.

This proves the mock TV speaks the same protocol as a real Android TV as far as
a widely used, independently written client is concerned, which is what makes
the Dart integration tests against the mock meaningful.

  pip install androidtvremote2 pyopenssl cryptography
  python3 tool/mock_tv/validate_mock.py
"""

from __future__ import annotations

import asyncio
import json
import os
import subprocess
import sys
import tempfile
import threading
import queue

from androidtvremote2 import AndroidTVRemote, CannotConnect, InvalidAuth

HERE = os.path.dirname(os.path.abspath(__file__))


class Mock:
    def __init__(self) -> None:
        self.proc = subprocess.Popen(
            [sys.executable, os.path.join(HERE, "mock_tv.py"), "--pair-port", "0", "--remote-port", "0", "--ping-interval", "0.5"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
        )
        self.events: "queue.Queue[dict]" = queue.Queue()
        self.log: list[dict] = []
        threading.Thread(target=self._read, daemon=True).start()
        ready = self.wait("ready")
        self.pair_port = ready["pair_port"]
        self.remote_port = ready["remote_port"]
        self.wol_port = ready["wol_port"]

    def command(self, line: str) -> None:
        assert self.proc.stdin
        self.proc.stdin.write(line + "\n")
        self.proc.stdin.flush()

    def magic_packet(self, mac: str) -> None:
        import socket

        payload = b"\xff" * 6 + bytes.fromhex(mac.replace(":", "")) * 16
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.sendto(payload, ("127.0.0.1", self.wol_port))

    def _read(self) -> None:
        assert self.proc.stdout
        for line in self.proc.stdout:
            event = json.loads(line)
            self.log.append(event)
            self.events.put(event)

    def wait(self, name: str, timeout: float = 10.0) -> dict:
        while True:
            event = self.events.get(timeout=timeout)
            if event["event"] == name:
                return event

    def close(self) -> None:
        assert self.proc.stdin
        self.proc.stdin.close()
        self.proc.wait(timeout=5)


async def main() -> None:
    mock = Mock()
    tmp = tempfile.mkdtemp()
    try:
        remote = AndroidTVRemote(
            "HAAM Remote",
            os.path.join(tmp, "cert.pem"),
            os.path.join(tmp, "key.pem"),
            "127.0.0.1",
            api_port=mock.remote_port,
            pair_port=mock.pair_port,
        )
        await remote.async_generate_cert_if_missing()

        # Unpaired certificate must be refused on the remote port.
        try:
            await remote.async_connect()
            raise AssertionError("unpaired client was accepted")
        except (InvalidAuth, CannotConnect):
            pass

        await remote.async_start_pairing()
        code = await asyncio.to_thread(mock.wait, "pairing_code")
        await remote.async_finish_pairing(code["code"])
        await asyncio.to_thread(mock.wait, "paired")

        await remote.async_connect()
        assert remote.device_info and remote.device_info["model"] == "R4", remote.device_info
        configured = await asyncio.to_thread(mock.wait, "configured")
        assert configured["features"] & 2, configured

        for key in ("DPAD_UP", "PROG_YELLOW", "VOLUME_UP"):
            remote.send_key_command(key)
        remote.send_launch_app_command("https://www.youtube.com")
        keys = [await asyncio.to_thread(mock.wait, "key") for _ in range(3)]
        assert [k["code"] for k in keys] == [19, 185, 24], keys
        assert all(k["direction"] == 3 for k in keys)
        link = await asyncio.to_thread(mock.wait, "app_link")
        assert link["link"] == "https://www.youtube.com"
        await asyncio.to_thread(mock.wait, "pong")
        await asyncio.sleep(0.3)
        assert remote.volume_info and remote.volume_info["level"] == 13, remote.volume_info

        # Wrong code must be rejected by the mock.
        other = AndroidTVRemote(
            "Other",
            os.path.join(tmp, "c2.pem"),
            os.path.join(tmp, "k2.pem"),
            "127.0.0.1",
            api_port=mock.remote_port,
            pair_port=mock.pair_port,
        )
        await other.async_generate_cert_if_missing()
        await other.async_start_pairing()
        real = (await asyncio.to_thread(mock.wait, "pairing_code"))["code"]
        wrong = real[:2] + ("0000" if real[2:] != "0000" else "0001")
        rejected = False
        try:
            await other.async_finish_pairing(wrong)
        except (InvalidAuth, CannotConnect, ConnectionError):
            rejected = True
        except Exception as exc:  # androidtvremote2 wraps the TV's error status
            rejected = "status" in str(exc).lower() or "closed" in type(exc).__name__.lower()
        assert rejected, "wrong code accepted"

        # Power state follows the power and wake-up keys, as on a real TV.
        assert remote.is_on is True, remote.is_on
        remote.send_key_command("POWER")
        assert (await asyncio.to_thread(mock.wait, "power"))["on"] is False
        await asyncio.sleep(0.3)
        assert remote.is_on is False, remote.is_on
        remote.send_key_command("WAKEUP")
        assert (await asyncio.to_thread(mock.wait, "power"))["on"] is True
        await asyncio.sleep(0.3)
        assert remote.is_on is True, remote.is_on
        remote.disconnect()

        # Deep sleep: nothing answers until a magic packet for the right MAC.
        mock.command("sleep")
        await asyncio.to_thread(mock.wait, "asleep")
        try:
            await remote.async_connect()
            raise AssertionError("a sleeping TV accepted a connection")
        except CannotConnect:
            pass
        mock.magic_packet("AA:BB:CC:DD:EE:99")
        await asyncio.to_thread(mock.wait, "wrong_magic_packet")
        mock.magic_packet("AA:BB:CC:DD:EE:0F")
        awake = await asyncio.to_thread(mock.wait, "awake")
        assert awake["screen_on"] is False, awake
        await remote.async_connect()
        await asyncio.sleep(0.3)
        assert remote.is_on is False, remote.is_on
        remote.send_key_command("WAKEUP")
        assert (await asyncio.to_thread(mock.wait, "power"))["on"] is True

        remote.disconnect()
        print("mock TV validated against androidtvremote2: OK")
    finally:
        mock.close()


if __name__ == "__main__":
    asyncio.run(main())
