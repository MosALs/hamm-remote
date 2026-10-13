import 'dart:convert';
import 'dart:typed_data';

import '../crypto/der.dart';
import '../crypto/identity.dart';

/// The phone's ADB key: the same RSA key as its TV-remote identity, in the
/// forms ADB needs (Android's public-key format and raw token signatures).
class AdbKey {
  AdbKey._(this._n, this._e, this._d, this._p, this._q);

  /// Reads the RSA numbers from the identity's PKCS#1 private key.
  factory AdbKey.fromIdentity(ClientIdentity identity) {
    final seq = DerNode.parse(pemToDer(identity.privateKeyPem)).children;
    // RSAPrivateKey ::= SEQUENCE { version, n, e, d, p, q, dp, dq, qinv }
    if (seq.length < 6) throw const FormatException('Not a PKCS#1 RSA private key');
    return AdbKey._(
      seq[1].unsignedInteger,
      seq[2].unsignedInteger,
      seq[3].unsignedInteger,
      seq[4].unsignedInteger,
      seq[5].unsignedInteger,
    );
  }

  final BigInt _n;
  final BigInt _e;
  final BigInt _d;
  final BigInt _p;
  final BigInt _q;

  int get _modulusBytes => (_n.bitLength + 7) ~/ 8;

  /// Android's `RSAPublicKey` struct (mincrypt layout), base64 encoded:
  /// word count, n0inv, modulus (little endian), R^2 mod n, exponent.
  String get publicKeyBase64 {
    final size = _modulusBytes;
    final words = size ~/ 4;
    final r32 = BigInt.one << 32;
    final n0inv = (r32 - (_n % r32).modInverse(r32)) % r32;
    final rr = (BigInt.one << (size * 8)).modPow(BigInt.two, _n);
    final out = ByteData(8 + size * 2 + 4)
      ..setUint32(0, words, Endian.little)
      ..setUint32(4, n0inv.toInt(), Endian.little);
    final bytes = out.buffer.asUint8List();
    bytes.setRange(8, 8 + size, _littleEndian(_n, size));
    bytes.setRange(8 + size, 8 + size * 2, _littleEndian(rr, size));
    out.setUint32(8 + size * 2, _e.toInt(), Endian.little);
    return base64.encode(bytes);
  }

  /// The payload of an AUTH(RSAPUBLICKEY) message.
  Uint8List publicKeyMessage({String comment = 'haam-remote@phone'}) =>
      Uint8List.fromList([...ascii.encode('$publicKeyBase64 $comment'), 0]);

  /// Signs the device's 20-byte token as ADB does: PKCS#1 v1.5 with the
  /// token used directly as a SHA-1 digest.
  Uint8List signToken(List<int> token) {
    const sha1DigestInfo = [
      0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, 0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14, //
    ];
    final k = _modulusBytes;
    final t = [...sha1DigestInfo, ...token];
    final padLength = k - t.length - 3;
    if (padLength < 8) throw ArgumentError('Key too small');
    final em = Uint8List(k)
      ..[0] = 0
      ..[1] = 1;
    em.fillRange(2, 2 + padLength, 0xFF);
    em[2 + padLength] = 0;
    em.setRange(3 + padLength, k, t);
    final m = Der.bigIntFromUnsigned(em);
    // Chinese remainder theorem: about 4x faster than m^d mod n.
    final dp = _d % (_p - BigInt.one);
    final dq = _d % (_q - BigInt.one);
    final qinv = _q.modInverse(_p);
    final m1 = m.modPow(dp, _p);
    final m2 = m.modPow(dq, _q);
    final h = (qinv * (m1 - m2)) % _p;
    final s = m2 + h * _q;
    return _bigEndian(s, k);
  }

  static Uint8List _littleEndian(BigInt value, int length) =>
      Uint8List.fromList(_bigEndian(value, length).reversed.toList());

  static Uint8List _bigEndian(BigInt value, int length) {
    final raw = Der.unsignedBytes(value);
    if (raw.length > length) throw ArgumentError('Value too large');
    return Uint8List(length)..setRange(length - raw.length, length, raw);
  }
}
