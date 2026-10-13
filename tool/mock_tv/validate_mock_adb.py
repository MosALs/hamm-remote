#!/usr/bin/env python3
"""Validate mock_adb.py against the reference ADB client `adb_shell`.

  pip install adb-shell cryptography
  python3 tool/mock_tv/validate_mock_adb.py

Also writes test/fixtures/adb_vectors.json when run with --vectors: the
Android-format public key that adb_shell produces for the fixed test
identity, so the Dart encoder is checked byte for byte against it.
"""

from __future__ import annotations

import json
import os
import queue
import subprocess
import sys
import tempfile
import threading

from adb_shell.adb_device import AdbDeviceTcp
from adb_shell.auth.keygen import encode_pubkey
from adb_shell.auth.sign_pythonrsa import PythonRSASigner

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))


def start_mock(*extra: str):
    proc = subprocess.Popen(
        [sys.executable, os.path.join(HERE, "mock_adb.py"), "--port", "0", *extra],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
    )
    events: "queue.Queue[dict]" = queue.Queue()

    def read() -> None:
        assert proc.stdout
        for line in proc.stdout:
            events.put(json.loads(line))

    threading.Thread(target=read, daemon=True).start()

    def wait(name: str, timeout: float = 10) -> dict:
        while True:
            e = events.get(timeout=timeout)
            if e["event"] == name:
                return e

    port = wait("ready")["port"]
    return proc, wait, port


def write_vectors() -> None:
    identity = json.load(open(os.path.join(ROOT, "test/fixtures/test_identity.json")))
    with tempfile.NamedTemporaryFile("w", suffix=".pem", delete=False) as f:
        f.write(identity["private_key_pem"])
        path = f.name
    import base64

    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding, utils

    key = serialization.load_pem_private_key(identity["private_key_pem"].encode(), password=None)
    token = bytes(range(20))
    signature = key.sign(token, padding.PKCS1v15(), utils.Prehashed(hashes.SHA1()))
    vectors = {
        "public_key_b64": base64.b64encode(encode_pubkey(path)).decode(),
        "token_hex": token.hex(),
        "signature_hex": signature.hex(),
    }
    out = os.path.join(ROOT, "test/fixtures/adb_vectors.json")
    with open(out, "w") as f:
        json.dump(vectors, f, indent=2)
        f.write("\n")
    print("wrote", out)


def main() -> None:
    if "--vectors" in sys.argv:
        write_vectors()
        return

    from adb_shell.auth.keygen import keygen

    tmp = tempfile.mkdtemp()
    keygen(os.path.join(tmp, "adbkey"))
    signer = PythonRSASigner.FromRSAKeyPath(os.path.join(tmp, "adbkey"))

    proc, wait, port = start_mock()
    try:
        device = AdbDeviceTcp("127.0.0.1", port, default_transport_timeout_s=5)
        assert device.connect(rsa_keys=[signer], auth_timeout_s=5)
        wait("auth_prompt")
        assert wait("connected")["known_key"] is False
        device.shell("input keyevent 183")
        assert wait("shell")["command"] == "input keyevent 183"
        device.close()

        # Second connection: the key is now known, no prompt.
        device = AdbDeviceTcp("127.0.0.1", port, default_transport_timeout_s=5)
        assert device.connect(rsa_keys=[signer], auth_timeout_s=5)
        assert wait("connected")["known_key"] is True
        device.shell("input keyevent 176")
        assert wait("shell")["command"] == "input keyevent 176"
        # Commands with output (the network interface list) arrive intact.
        links = device.shell("ip -o link")
        assert "wlan0:" in links and "link/ether aa:bb:cc:dd:ee:10" in links, links
        device.close()
        print("mock ADB device validated against adb_shell: OK")
    finally:
        assert proc.stdin
        proc.stdin.close()
        proc.wait(timeout=5)


if __name__ == "__main__":
    main()
