import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'der.dart';

/// RSA public key numbers.
class RsaPublicNumbers {
  const RsaPublicNumbers(this.modulus, this.exponent);

  final BigInt modulus;
  final BigInt exponent;
}

/// The phone's TLS identity: a self-signed certificate and its RSA key.
/// The TV remembers this certificate when pairing succeeds, so it must be
/// generated once and kept.
class ClientIdentity {
  ClientIdentity({required this.certificatePem, required this.privateKeyPem})
      : certificateDer = pemToDer(certificatePem),
        publicKey = rsaPublicKeyFromCertificate(pemToDer(certificatePem));

  final String certificatePem;
  final String privateKeyPem;
  final Uint8List certificateDer;
  final RsaPublicNumbers publicKey;

  /// Generates a 2048-bit RSA key and a self-signed certificate like the
  /// official remote apps use. Takes a few seconds on a phone: run it in a
  /// background isolate.
  static ClientIdentity generate({String commonName = 'atvremote', Random? seedSource}) {
    final rng = seedSource ?? Random.secure();
    final secureRandom = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)))));

    final generator = RSAKeyGenerator()
      ..init(ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
        secureRandom,
      ));
    final pair = generator.generateKeyPair();
    final publicKey = pair.publicKey;
    final privateKey = pair.privateKey;

    final now = DateTime.now().toUtc();
    final serial = BigInt.parse(
      List<String>.generate(16, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join(),
      radix: 16,
    ) >> 1; // keep it positive and within 20 octets
    final name = Der.sequence([
      Der.setOf([
        Der.sequence([Der.oid('2.5.4.3'), Der.utf8String(commonName)]),
      ]),
    ]);
    final sha256WithRsa = Der.sequence([Der.oid('1.2.840.113549.1.1.11'), Der.nullValue()]);
    final rsaEncryption = Der.sequence([Der.oid('1.2.840.113549.1.1.1'), Der.nullValue()]);
    final rsaPublicKey = Der.sequence([
      Der.integer(publicKey.modulus!),
      Der.integer(publicKey.publicExponent!),
    ]);
    final extensions = Der.sequence([
      // basicConstraints: CA:TRUE, pathlen:0 (mirrors the reference clients).
      Der.sequence([
        Der.oid('2.5.29.19'),
        Der.octetString(Der.sequence([Der.boolean(true), Der.smallInteger(0)])),
      ]),
      // subjectAltName: DNS:<commonName>
      Der.sequence([
        Der.oid('2.5.29.17'),
        Der.octetString(Der.sequence([Der.implicitPrimitive(2, ascii.encode(commonName))])),
      ]),
    ]);
    final tbs = Der.sequence([
      Der.explicit(0, Der.smallInteger(2)), // v3
      Der.integer(serial == BigInt.zero ? BigInt.one : serial),
      sha256WithRsa,
      name,
      Der.sequence([
        Der.time(now.subtract(const Duration(days: 1))),
        Der.time(now.add(const Duration(days: 3650 * 3))),
      ]),
      name,
      Der.sequence([rsaEncryption, Der.bitString(rsaPublicKey)]),
      Der.explicit(3, extensions),
    ]);

    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(privateKey));
    final signature = signer.generateSignature(tbs).bytes;
    final certificate = Der.sequence([tbs, sha256WithRsa, Der.bitString(signature)]);

    final p = privateKey.p!;
    final q = privateKey.q!;
    final d = privateKey.privateExponent!;
    final pkcs1 = Der.sequence([
      Der.smallInteger(0),
      Der.integer(privateKey.modulus!),
      Der.integer(publicKey.publicExponent!),
      Der.integer(d),
      Der.integer(p),
      Der.integer(q),
      Der.integer(d % (p - BigInt.one)),
      Der.integer(d % (q - BigInt.one)),
      Der.integer(q.modInverse(p)),
    ]);

    return ClientIdentity(
      certificatePem: derToPem(certificate, 'CERTIFICATE'),
      privateKeyPem: derToPem(pkcs1, 'RSA PRIVATE KEY'),
    );
  }
}

/// Extracts the RSA modulus and exponent from a DER X.509 certificate.
RsaPublicNumbers rsaPublicKeyFromCertificate(List<int> der) {
  final certificate = DerNode.parse(der);
  final tbs = certificate.children.first;
  final fields = tbs.children;
  // TBSCertificate: [0] version (optional), serial, signature, issuer,
  // validity, subject, subjectPublicKeyInfo, ...
  final base = fields.first.tag == 0xA0 ? 1 : 0;
  if (fields.length < base + 6) throw const FormatException('Malformed certificate');
  final spki = fields[base + 5];
  final bitString = spki.children[1];
  if (bitString.tag != Der.tagBitString || bitString.content.isEmpty) {
    throw const FormatException('Malformed public key');
  }
  final rsaKey = DerNode.parse(Uint8List.sublistView(bitString.content, 1)).children;
  return RsaPublicNumbers(rsaKey[0].unsignedInteger, rsaKey[1].unsignedInteger);
}

/// Computes the pairing secret for the 6-hex-digit [code] shown on the TV.
///
/// The TV hashes, with SHA-256, the client modulus, client exponent, server
/// modulus, server exponent (each as minimal unsigned big-endian bytes) and
/// the last two bytes of the code. The first byte of the hash is the first
/// byte of the code, which lets us detect typos before sending anything.
///
/// Returns null when [code] does not match (typo or wrong TV).
Uint8List? pairingSecret({
  required RsaPublicNumbers client,
  required RsaPublicNumbers server,
  required String code,
}) {
  final normalized = normalizePairingCode(code);
  if (normalized == null) return null;
  final digest = SHA256Digest();
  void add(List<int> bytes) => digest.update(Uint8List.fromList(bytes), 0, bytes.length);
  add(Der.unsignedBytes(client.modulus));
  add(Der.unsignedBytes(client.exponent));
  add(Der.unsignedBytes(server.modulus));
  add(Der.unsignedBytes(server.exponent));
  add(hexToBytes(normalized.substring(2)));
  final out = Uint8List(digest.digestSize);
  digest.doFinal(out, 0);
  return out[0] == int.parse(normalized.substring(0, 2), radix: 16) ? out : null;
}

/// Uppercases and validates a pairing code: exactly 6 hex digits.
String? normalizePairingCode(String code) {
  final c = code.trim().toUpperCase();
  return RegExp(r'^[0-9A-F]{6}$').hasMatch(c) ? c : null;
}

String sha256Hex(List<int> data) {
  final digest = SHA256Digest();
  final out = digest.process(Uint8List.fromList(data));
  return out.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Uint8List hexToBytes(String hex) {
  final clean = hex.length.isOdd ? '0$hex' : hex;
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2) int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}

Uint8List pemToDer(String pem) {
  final body = pem
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('-----'))
      .join();
  return base64.decode(body);
}

String derToPem(List<int> der, String label) {
  final b64 = base64.encode(der);
  final lines = <String>[
    for (var i = 0; i < b64.length; i += 64) b64.substring(i, min(i + 64, b64.length)),
  ];
  return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
}
