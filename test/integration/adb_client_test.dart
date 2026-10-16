@Timeout(Duration(minutes: 2))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:haam_remote/src/adb/adb_client.dart';
import 'package:haam_remote/src/adb/adb_key.dart';
import 'package:haam_remote/src/crypto/identity.dart';
import 'package:haam_remote/src/protocol/errors.dart';

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

    test('a TV that hangs up mid-handshake is reported, not crashed', () async {
      // The TV sends its token and drops the connection, so the phone's
      // signature is written into a reset socket.
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((socket) {
        socket.listen((_) {
          socket.add(AdbMessage(AdbMessage.auth, AdbMessage.authToken, 0, Uint8List(20)).encode());
          socket.destroy();
        });
      });
      await expectLater(
        AdbClient.connect(host: '127.0.0.1', port: server.port, key: key),
        throwsA(isA<TvException>()),
      );
      // Any late write error would surface here and fail the test.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    test('installs an app by streaming it in chunks the device accepts', () async {
      final adb = await MockAdb.start(maxPayload: 4096);
      addTearDown(adb.close);
      final client = await AdbClient.connect(host: '127.0.0.1', port: adb.port, key: key);
      addTearDown(client.close);
      // 50 KB that looks like an APK (a zip), so it spans many messages.
      final apk = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, for (var i = 0; i < 50000; i++) i * 7 & 0xFF]);
      expect(await client.install(apk), contains('Success'));
      expect((await adb.waitFor('exec'))['command'], 'cmd package install -r -S ${apk.length}');
      final installed = await adb.waitFor('install');
      expect(installed['size'], apk.length);
      expect(installed['sha256'], sha256Hex(apk));
      expect(adb.events.where((e) => e['event'] == 'error'), isEmpty);

      // The connection stays usable, and a refused install is reported.
      expect(await client.shell('pm list packages com.haam.keepawake'), contains('package:com.haam.keepawake'));
      await expectLater(client.install(Uint8List.fromList([1, 2, 3])), throwsA(isA<TvProtocolError>()));
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
