import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:haam_remote/src/adb/adb_client.dart';
import 'package:haam_remote/src/adb/adb_key.dart';
import 'package:haam_remote/src/crypto/identity.dart';

import 'support/test_identity.dart';

void main() {
  final key = AdbKey.fromIdentity(loadTestIdentity());
  final vectors =
      jsonDecode(File('test/fixtures/adb_vectors.json').readAsStringSync()) as Map<String, dynamic>;

  test('public key matches the reference encoder byte for byte', () {
    expect(key.publicKeyBase64, vectors['public_key_b64']);
    final message = key.publicKeyMessage(comment: 'me@phone');
    expect(message.last, 0);
    expect(ascii.decode(message.sublist(0, message.length - 1)), '${vectors['public_key_b64']} me@phone');
  });

  test('signs the auth token like the reference client', () {
    final token = hexToBytes(vectors['token_hex'] as String);
    final signature = key.signToken(token);
    expect(signature.map((b) => b.toRadixString(16).padLeft(2, '0')).join(), vectors['signature_hex']);
  });

  test('messages round-trip through the framer, split anywhere', () {
    final messages = [
      AdbMessage(AdbMessage.cnxn, 0x01000000, 4096, Uint8List.fromList(ascii.encode('host::\x00'))),
      AdbMessage(AdbMessage.okay, 7, 1, Uint8List(0)),
      AdbMessage(AdbMessage.wrte, 7, 1, Uint8List.fromList(List<int>.generate(300, (i) => i % 256))),
    ];
    final stream = [for (final m in messages) ...m.encode()];
    for (var split = 0; split <= stream.length; split += 7) {
      final framer = AdbFramer();
      final out = [...framer.add(stream.sublist(0, split)), ...framer.add(stream.sublist(split))];
      expect(out.map((m) => m.command), messages.map((m) => m.command));
      expect(out.last.data, messages.last.data);
    }
  });

  test('command codes are the ASCII names', () {
    expect(AdbMessage.cnxn, 0x4e584e43);
    expect(AdbMessage.auth, 0x48545541);
  });
}
