#!/usr/bin/env python3
"""A mock Android TV that speaks the Android TV Remote protocol v2.

It is used by the Dart integration tests (test/integration/) and was validated
against the reference Python client `androidtvremote2` (see validate_mock.py),
so it behaves like the real "Android TV Remote Service" on a TV:

* Pairing port: TLS with a client certificate (any certificate accepted),
  polo handshake, a 6-hex-digit code that is "shown on screen" (printed as a
  JSON event on stdout), and a secret check.
* Remote port: TLS that only accepts paired client certificates, then the
  configure / set_active / start handshake, periodic pings, key events and
  app-link launches.

Every observable event is printed to stdout as one JSON object per line, e.g.
  {"event": "ready", "pair_port": 41234, "remote_port": 41235}
  {"event": "pairing_code", "code": "4FA1C9"}
  {"event": "paired", "client": "HAAM Remote"}
  {"event": "key", "code": 19, "direction": 3}

Dependencies: cryptography, pyOpenSSL.
"""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import secrets
import socket
import sys
import threading
import time

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID
from OpenSSL import SSL, crypto

# --------------------------------------------------------------------------
# Minimal protobuf codec (enough for the polo and remote messages).
# --------------------------------------------------------------------------


def _varint(value: int) -> bytes:
    if value < 0:
        value += 1 << 64
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        if value:
            out.append(byte | 0x80)
        else:
            out.append(byte)
            return bytes(out)


def encode(fields: list[tuple[int, object]]) -> bytes:
    """Encode [(field_number, value)] where value is int, bool, str, bytes or a nested list."""
    out = bytearray()
    for number, value in fields:
        if isinstance(value, bool):
            out += _varint(number << 3) + _varint(int(value))
        elif isinstance(value, int):
            out += _varint(number << 3) + _varint(value)
        else:
            if isinstance(value, str):
                payload = value.encode()
            elif isinstance(value, (bytes, bytearray)):
                payload = bytes(value)
            else:
                payload = encode(value)  # nested message
            out += _varint((number << 3) | 2) + _varint(len(payload)) + payload
    return bytes(out)


def _read_varint(data: bytes, pos: int) -> tuple[int, int]:
    shift = 0
    result = 0
    while True:
        if pos >= len(data):
            raise ValueError("truncated varint")
        byte = data[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return result, pos
        shift += 7


def decode(data: bytes) -> dict[int, list[object]]:
    """Decode to {field_number: [values]}; varints become int, length-delimited stay bytes."""
    fields: dict[int, list[object]] = {}
    pos = 0
    while pos < len(data):
        key, pos = _read_varint(data, pos)
        number, wire = key >> 3, key & 7
        if wire == 0:
            value, pos = _read_varint(data, pos)
        elif wire == 2:
            length, pos = _read_varint(data, pos)
            value = data[pos : pos + length]
            pos += length
        elif wire == 5:
            value = data[pos : pos + 4]
            pos += 4
        elif wire == 1:
            value = data[pos : pos + 8]
            pos += 8
        else:
            raise ValueError(f"unsupported wire type {wire}")
        fields.setdefault(number, []).append(value)
    return fields


def first(fields: dict[int, list[object]], number: int, default=None):
    values = fields.get(number)
    return values[0] if values else default


# --------------------------------------------------------------------------
# Framing: each message is prefixed with its length as a varint.
# --------------------------------------------------------------------------


class Framed:
    def __init__(self, conn: SSL.Connection) -> None:
        self.conn = conn
        self.buf = bytearray()
        self.lock = threading.Lock()

    def send(self, payload: bytes) -> None:
        with self.lock:
            self.conn.sendall(_varint(len(payload)) + payload)

    def recv(self) -> bytes | None:
        while True:
            try:
                length, pos = _read_varint(bytes(self.buf), 0)
                if len(self.buf) >= pos + length:
                    msg = bytes(self.buf[pos : pos + length])
                    del self.buf[: pos + length]
                    return msg
            except ValueError:
                pass
            try:
                chunk = self.conn.recv(65536)
            except (SSL.ZeroReturnError, SSL.SysCallError, ConnectionError, OSError):
                return None
            except SSL.Error:
                return None
            if not chunk:
                return None
            self.buf += chunk


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

_print_lock = threading.Lock()


def emit(event: str, **data: object) -> None:
    with _print_lock:
        sys.stdout.write(json.dumps({"event": event, **data}) + "\n")
        sys.stdout.flush()


def make_server_identity() -> tuple[bytes, bytes, x509.Certificate]:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "atvremote/R4/R4/AA:BB:CC:DD:EE:0F")])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(now - datetime.timedelta(days=1))
        .not_valid_after(now + datetime.timedelta(days=3650))
        .sign(key, hashes.SHA256())
    )
    key_pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.TraditionalOpenSSL,
        serialization.NoEncryption(),
    )
    return cert.public_bytes(serialization.Encoding.PEM), key_pem, cert


def unsigned_bytes(value: int) -> bytes:
    """Minimal big-endian unsigned bytes, as the polo protocol hashes RSA numbers."""
    return value.to_bytes(max(1, (value.bit_length() + 7) // 8), "big")


def pairing_hash(client_cert: x509.Certificate, server_cert: x509.Certificate, nonce: bytes) -> bytes:
    """SHA-256 over client modulus, client exponent, server modulus, server exponent, nonce."""
    c = client_cert.public_key().public_numbers()
    s = server_cert.public_key().public_numbers()
    h = hashlib.sha256()
    for number in (c.n, c.e, s.n, s.e):
        h.update(unsigned_bytes(number))
    h.update(nonce)
    return h.digest()


def fingerprint(cert: x509.Certificate) -> str:
    return cert.fingerprint(hashes.SHA256()).hex()


# --------------------------------------------------------------------------
# Server
# --------------------------------------------------------------------------

FEATURES = 2 | 1 | 4 | 32 | 64 | 512  # KEY | PING | IME | POWER | VOLUME | APP_LINK


class MockTv:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.cert_pem, self.key_pem, self.cert = make_server_identity()
        self.paired: set[str] = set()
        self.volume = 12
        self.muted = False
        self.lock = threading.Lock()

    # -- TLS ------------------------------------------------------------
    def _context(self, paired_only: bool) -> SSL.Context:
        ctx = SSL.Context(SSL.TLS_SERVER_METHOD)
        ctx.use_certificate(crypto.load_certificate(crypto.FILETYPE_PEM, self.cert_pem))
        ctx.use_privatekey(crypto.load_privatekey(crypto.FILETYPE_PEM, self.key_pem))

        def verify(_conn, cert, _errno, depth, _ok) -> bool:
            # Pairing accepts any client certificate. The remote port, like the
            # real TV, fails the TLS handshake for certificates it never paired.
            if not paired_only or depth > 0:
                return True
            with self.lock:
                return fingerprint(cert.to_cryptography()) in self.paired

        ctx.set_verify(SSL.VERIFY_PEER | SSL.VERIFY_FAIL_IF_NO_PEER_CERT, verify)
        return ctx

    def _listen(self, port: int) -> socket.socket:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind((self.args.host, port))
        sock.listen(8)
        return sock

    def _accept_loop(self, sock: socket.socket, handler) -> None:
        while True:
            raw, addr = sock.accept()
            threading.Thread(target=self._serve, args=(raw, handler), daemon=True).start()

    def _serve(self, raw: socket.socket, handler) -> None:
        conn = SSL.Connection(self._context(paired_only=handler == self.handle_remote), raw)
        conn.set_accept_state()
        try:
            conn.do_handshake()
        except SSL.Error as exc:
            if handler == self.handle_remote:
                emit("remote_rejected")
            else:
                emit("tls_error", detail=str(exc))
            raw.close()
            return
        peer = conn.get_peer_certificate()
        client_cert = peer.to_cryptography() if peer is not None else None
        try:
            handler(Framed(conn), client_cert)
        finally:
            try:
                conn.shutdown()
            except SSL.Error:
                pass
            raw.close()

    # -- Pairing --------------------------------------------------------
    def _polo(self, **fields) -> bytes:
        out: list[tuple[int, object]] = [(1, 2), (2, fields.pop("status", 200))]
        for number, value in fields.items():
            out.append((int(number[1:]), value))
        return encode(out)

    def handle_pairing(self, ch: Framed, client_cert: x509.Certificate | None) -> None:
        if client_cert is None:
            return
        client_name = ""
        nonce = b""
        while True:
            raw = ch.recv()
            if raw is None:
                return
            msg = decode(raw)
            if first(msg, 2) != 200:
                emit("pairing_error", detail="client status not OK")
                return
            if 10 in msg:  # pairing_request
                req = decode(first(msg, 10))
                client_name = (first(req, 2) or b"").decode()
                service = (first(req, 1) or b"").decode()
                emit("pairing_request", client=client_name, service=service)
                ch.send(self._polo(f11=[(1, "Mock R4")]))
            elif 20 in msg:  # options
                opts = decode(first(msg, 20))
                enc = decode(first(opts, 1) or b"")
                if first(enc, 1) != 3 or first(enc, 2) != 6:
                    ch.send(self._polo(status=401))
                    return
                ch.send(self._polo(f20=[(1, [(1, 3), (2, 6)]), (3, 1)]))
            elif 30 in msg:  # configuration
                conf = decode(first(msg, 30))
                enc = decode(first(conf, 1) or b"")
                if first(enc, 1) != 3 or first(enc, 2) != 6 or first(conf, 2) != 1:
                    ch.send(self._polo(status=401))
                    return
                nonce = secrets.token_bytes(2)
                digest = pairing_hash(client_cert, self.cert, nonce)
                code = f"{digest[0]:02X}{nonce.hex().upper()}"
                ch.send(self._polo(f31=b""))
                emit("pairing_code", code=code)
            elif 40 in msg:  # secret
                secret = first(decode(first(msg, 40)), 1) or b""
                expected = pairing_hash(client_cert, self.cert, nonce)
                if not nonce or secret != expected:
                    emit("pairing_failed", client=client_name)
                    ch.send(self._polo(status=402))
                    return
                with self.lock:
                    self.paired.add(fingerprint(client_cert))
                ch.send(self._polo(f41=[(1, expected)]))
                emit("paired", client=client_name)
                return
            else:
                ch.send(self._polo(status=400))
                return

    # -- Remote ---------------------------------------------------------
    def _volume_msg(self) -> bytes:
        return encode([(50, [(3, "mock"), (6, 100), (7, self.volume), (8, self.muted)])])

    def handle_remote(self, ch: Framed, client_cert: x509.Certificate | None) -> None:
        with self.lock:
            is_paired = client_cert is not None and fingerprint(client_cert) in self.paired
        if not is_paired:
            emit("remote_rejected")
            return  # the real TV drops unpaired clients right after the handshake
        emit("remote_connected")
        ch.send(encode([(1, [(1, FEATURES), (2, [(1, "R4"), (2, "TCL"), (3, 1), (4, "1"), (6, "1.0")])])]))
        stop = threading.Event()
        pong = {"last": time.monotonic()}

        def pinger() -> None:
            n = 0
            while not stop.wait(self.args.ping_interval):
                n += 1
                try:
                    ch.send(encode([(8, [(1, n), (2, 0)])]))
                except (SSL.Error, OSError):
                    return
                if time.monotonic() - pong["last"] > self.args.ping_interval * 4:
                    emit("ping_timeout")
                    try:
                        ch.conn.shutdown()
                    except SSL.Error:
                        pass
                    return

        threading.Thread(target=pinger, daemon=True).start()
        try:
            while True:
                raw = ch.recv()
                if raw is None:
                    emit("remote_disconnected")
                    return
                msg = decode(raw)
                if 1 in msg:  # remote_configure reply
                    cfg = decode(first(msg, 1))
                    info = decode(first(cfg, 2) or b"")
                    emit("configured", features=first(cfg, 1, 0), package=(first(info, 5) or b"").decode())
                    ch.send(encode([(2, [(1, FEATURES)])]))
                elif 2 in msg:  # remote_set_active reply
                    emit("active", features=first(decode(first(msg, 2)), 1, 0))
                    ch.send(encode([(40, [(1, True)])]))
                    ch.send(self._volume_msg())
                elif 9 in msg:  # ping response
                    pong["last"] = time.monotonic()
                    emit("pong", val=first(decode(first(msg, 9)), 1, 0))
                elif 10 in msg:  # key inject
                    key = decode(first(msg, 10))
                    code = first(key, 1, 0)
                    direction = first(key, 2, 0)
                    emit("key", code=code, direction=direction)
                    if direction in (3, 1) and code in (24, 25, 164):
                        with self.lock:
                            if code == 24:
                                self.volume = min(100, self.volume + 1)
                            elif code == 25:
                                self.volume = max(0, self.volume - 1)
                            else:
                                self.muted = not self.muted
                        ch.send(self._volume_msg())
                elif 21 in msg:  # ime batch edit (text)
                    batch = decode(first(msg, 21))
                    edit = decode(first(batch, 3) or b"")
                    obj = decode(first(edit, 2) or b"")
                    emit("text", value=(first(obj, 3) or b"").decode())
                elif 90 in msg:  # app link
                    link = (first(decode(first(msg, 90)), 1) or b"").decode()
                    emit("app_link", link=link)
                else:
                    emit("unknown", fields=sorted(msg))
        finally:
            stop.set()

    # -- Main -----------------------------------------------------------
    def run(self) -> None:
        pair_sock = self._listen(self.args.pair_port)
        remote_sock = self._listen(self.args.remote_port)
        threading.Thread(target=self._accept_loop, args=(pair_sock, self.handle_pairing), daemon=True).start()
        threading.Thread(target=self._accept_loop, args=(remote_sock, self.handle_remote), daemon=True).start()
        emit("ready", pair_port=pair_sock.getsockname()[1], remote_port=remote_sock.getsockname()[1])
        try:
            # Exit when stdin closes so test harnesses never leak the process.
            for _ in sys.stdin:
                pass
        except KeyboardInterrupt:
            pass
        os._exit(0)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--pair-port", type=int, default=6467)
    parser.add_argument("--remote-port", type=int, default=6466)
    parser.add_argument("--ping-interval", type=float, default=5.0)
    MockTv(parser.parse_args()).run()


if __name__ == "__main__":
    main()
