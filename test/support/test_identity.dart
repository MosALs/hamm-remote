import 'dart:convert';
import 'dart:io';

import 'package:haam_remote/src/crypto/identity.dart';

/// A fixed phone identity (tool/mock_tv/gen_vectors.py --identity), so tests
/// don't spend seconds generating RSA keys. Key generation itself is tested
/// in crypto_test.dart.
ClientIdentity loadTestIdentity() {
  final json = jsonDecode(File('test/fixtures/test_identity.json').readAsStringSync()) as Map<String, dynamic>;
  return ClientIdentity(
    certificatePem: json['certificate_pem'] as String,
    privateKeyPem: json['private_key_pem'] as String,
  );
}
