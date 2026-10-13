#!/usr/bin/env python3
"""Generate test/fixtures/pairing_vectors.json for the Dart unit tests.

The vectors pin the pairing-secret computation and certificate parsing to an
independent implementation (Python `cryptography` + the same hashing that the
reference client `androidtvremote2` uses with real TVs).

  python3 tool/mock_tv/gen_vectors.py > test/fixtures/pairing_vectors.json
  python3 tool/mock_tv/gen_vectors.py --identity test/fixtures/test_identity.json
"""

from __future__ import annotations

import datetime
import hashlib
import json
import os
import sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mock_tv import pairing_hash  # noqa: E402


def cert_for(key: rsa.RSAPrivateKey, cn: str, long_length: bool) -> x509.Certificate:
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)])
    builder = (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(1000)
        .not_valid_before(datetime.datetime(2024, 1, 1, tzinfo=datetime.timezone.utc))
        .not_valid_after(datetime.datetime(2060, 1, 1, tzinfo=datetime.timezone.utc))
    )
    if long_length:
        builder = builder.add_extension(x509.SubjectAlternativeName([x509.DNSName("x" * 60 + ".local")]), False)
    return builder.sign(key, hashes.SHA256())


def vector(client_exp: int, server_bits: int, nonce: bytes, label: str) -> dict:
    client_key = rsa.generate_private_key(public_exponent=client_exp, key_size=2048)
    server_key = rsa.generate_private_key(public_exponent=65537, key_size=server_bits)
    client_cert = cert_for(client_key, "atvremote", False)
    server_cert = cert_for(server_key, "atvremote/TCL/R4", True)
    digest = pairing_hash(client_cert, server_cert, nonce)
    c = client_cert.public_key().public_numbers()
    s = server_cert.public_key().public_numbers()
    return {
        "label": label,
        "client_cert_pem": client_cert.public_bytes(serialization.Encoding.PEM).decode(),
        "server_cert_der_hex": server_cert.public_bytes(serialization.Encoding.DER).hex(),
        "client_modulus_hex": f"{c.n:x}",
        "client_exponent": c.e,
        "server_modulus_hex": f"{s.n:x}",
        "server_exponent": s.e,
        "code": f"{digest[0]:02X}{nonce.hex().upper()}",
        "secret_hex": digest.hex(),
        "server_sha256": hashlib.sha256(server_cert.public_bytes(serialization.Encoding.DER)).hexdigest(),
    }


def main() -> None:
    vectors = [
        vector(65537, 2048, bytes.fromhex("4fa1"), "typical 2048-bit keys"),
        vector(3, 1024, bytes.fromhex("00ff"), "exponent 3, 1024-bit server key"),
    ]
    json.dump({"vectors": vectors}, sys.stdout, indent=2)
    sys.stdout.write("\n")


def write_test_identity(path: str) -> None:
    """A fixed client identity so tests don't spend seconds generating RSA keys."""
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    cert = cert_for(key, "atvremote", False)
    data = {
        "certificate_pem": cert.public_bytes(serialization.Encoding.PEM).decode(),
        "private_key_pem": key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.TraditionalOpenSSL,
            serialization.NoEncryption(),
        ).decode(),
    }
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--identity":
        write_test_identity(sys.argv[2])
    else:
        main()
