@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haam_remote/src/adb/adb_client.dart';
import 'package:haam_remote/src/adb/adb_key.dart';

import '../support/mock_adb.dart';
import '../support/mock_tv.dart';
import '../support/test_identity.dart';

void main() {
  final unavailable = MockTv.unavailableReason();
  if (unavailable != null && Platform.environment['REQUIRE_MOCK_TV'] == '1') {
    throw StateError('Mock devices required in CI but unavailable: $unavailable');
  }
  final key = AdbKey.fromIdentity(loadTestIdentity());

  group('ADB against the mock device', () {
    test('first connection asks the TV, then keys and apps go through', () async {
      final adb = await MockAdb.start();
      addTearDown(adb.close);
      var asked = false;
      final client = await AdbClient.connect(
        host: '127.0.0.1',
        port: adb.port,
        key: key,
        onApprovalNeeded: () => asked = true,
      );
      addTearDown(client.close);
      expect(asked, isTrue);
      expect((await adb.waitFor('auth_prompt'))['key_comment'], 'haam-remote@phone');
      expect((await adb.waitFor('connected'))['known_key'], isFalse);

      await client.keyEvent(185);
      expect((await adb.waitFor('shell'))['command'], 'input keyevent 185');
      await Future.wait([client.keyEvent(178), client.keyEvent(176)]);
      expect((await adb.waitFor('shell'))['command'], 'input keyevent 178');
      expect((await adb.waitFor('shell'))['command'], 'input keyevent 176');
      client.close();

      // The key is remembered: no prompt the second time.
      var askedAgain = false;
      final again = await AdbClient.connect(
        host: '127.0.0.1',
        port: adb.port,
        key: key,
        onApprovalNeeded: () => askedAgain = true,
      );
      addTearDown(again.close);
      expect(askedAgain, isFalse);
      expect((await adb.waitFor('connected'))['known_key'], isTrue);
    });

    test('an unanswered prompt is reported as not authorized', () async {
      final adb = await MockAdb.start(reject: true);
      addTearDown(adb.close);
      await expectLater(
        AdbClient.connect(
          host: '127.0.0.1',
          port: adb.port,
          key: key,
          approvalTimeout: const Duration(seconds: 1),
        ),
        throwsA(isA<AdbNotAuthorized>()),
      );
    });

    test('debugging turned off is reported as unreachable', () async {
      await expectLater(
        AdbClient.connect(host: '127.0.0.1', port: 1, key: key),
        throwsA(isA<Exception>()),
      );
    });
  }, skip: unavailable);
}
