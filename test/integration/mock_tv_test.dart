import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haam_remote/src/crypto/identity.dart';
import 'package:haam_remote/src/protocol/errors.dart';
import 'package:haam_remote/src/protocol/keycodes.dart';
import 'package:haam_remote/src/protocol/messages.dart';
import 'package:haam_remote/src/protocol/pairing.dart';
import 'package:haam_remote/src/protocol/remote_session.dart';

import '../support/mock_tv.dart';
import '../support/test_identity.dart';

/// End-to-end: the real Dart protocol client against the simulated TV.
void main() {
  final unavailable = MockTv.unavailableReason();
  if (unavailable != null && Platform.environment['REQUIRE_MOCK_TV'] == '1') {
    throw StateError('Mock TV required in CI but unavailable: $unavailable');
  }

  group('against the mock TV', () {
    late MockTv tv;
    late ClientIdentity identity;

    setUpAll(() => identity = loadTestIdentity());
    setUp(() async => tv = await MockTv.start());
    tearDown(() => tv.close());

    Future<String> pair(ClientIdentity id) async {
      final session = await PairingSession.start(host: '127.0.0.1', port: tv.pairPort, identity: id);
      final request = await tv.waitFor('pairing_request');
      expect(request['client'], 'HAAM Remote');
      expect(request['service'], 'atvremote');
      final code = (await tv.waitFor('pairing_code'))['code'] as String;
      await session.finish(code);
      await tv.waitFor('paired');
      return session.serverFingerprint;
    }

    test('an unpaired phone is told to pair', () async {
      await expectLater(
        RemoteSession.connect(host: '127.0.0.1', port: tv.remotePort, identity: identity),
        throwsA(isA<TvNeedsPairing>()),
      );
    });

    test('pairs, connects and delivers keys, apps and text', () async {
      final fingerprint = await pair(identity);
      final session = await RemoteSession.connect(
        host: '127.0.0.1',
        port: tv.remotePort,
        identity: identity,
        expectedServerFingerprint: fingerprint,
      );
      addTearDown(session.close);

      final configured = await tv.waitFor('configured');
      expect(configured['features'] & Remote.featureKey, isNot(0));
      expect(configured['package'], 'com.haam.remote');
      await tv.waitFor('active');
      expect(session.model, 'R4');
      expect(session.vendor, 'TCL');
      expect(session.isOn, isTrue);

      for (final key in [KeyCode.dpadUp, KeyCode.yellow, KeyCode.blue, KeyCode.dpadCenter]) {
        session.sendKey(key);
      }
      final keys = [for (var i = 0; i < 4; i++) await tv.waitFor('key')];
      expect([for (final k in keys) k['code']], [19, 185, 186, 23]);
      expect([for (final k in keys) k['direction']], everyElement(3));

      session.sendKey(KeyCode.dpadDown, KeyDirection.startLong);
      session.sendKey(KeyCode.dpadDown, KeyDirection.endLong);
      expect((await tv.waitFor('key'))['direction'], 1);
      expect((await tv.waitFor('key'))['direction'], 2);

      final volume = session.events
          .firstWhere((e) => e is VolumeChanged && e.volume.level == 13)
          .timeout(const Duration(seconds: 5));
      session.sendKey(KeyCode.volumeUp);
      final changed = await volume as VolumeChanged;
      expect(changed.volume.level, 13);
      expect(changed.volume.max, 100);

      session.launchApp(TvApp.shahid.launchLink);
      expect((await tv.waitFor('app_link'))['link'], 'market://launch?id=net.mbc.shahidTV');

      session.sendText('الجزيرة');
      expect((await tv.waitFor('text'))['value'], 'الجزيرة');

      // The session answers the TV's pings and stays up.
      await tv.waitFor('pong');
      await tv.waitFor('pong');
      expect(session.isOpen, isTrue);
    });

    test('a mistyped code is caught locally and can be retried', () async {
      final session = await PairingSession.start(host: '127.0.0.1', port: tv.pairPort, identity: identity);
      final code = (await tv.waitFor('pairing_code'))['code'] as String;
      final first = int.parse(code.substring(0, 2), radix: 16);
      final typo = '${((first + 1) % 256).toRadixString(16).padLeft(2, '0')}${code.substring(2)}';
      await expectLater(session.finish(typo), throwsA(isA<PairingCodeMismatch>()));
      expect(session.isOpen, isTrue);
      await session.finish(code.toLowerCase());
      await tv.waitFor('paired');
    });

    test('a changed TV identity requires pairing again', () async {
      await pair(identity);
      await expectLater(
        RemoteSession.connect(
          host: '127.0.0.1',
          port: tv.remotePort,
          identity: identity,
          expectedServerFingerprint: 'not-the-real-fingerprint',
        ),
        throwsA(isA<TvNeedsPairing>()),
      );
    });

    test('reports a closed session when the TV goes away', () async {
      final fingerprint = await pair(identity);
      final session = await RemoteSession.connect(
        host: '127.0.0.1',
        port: tv.remotePort,
        identity: identity,
        expectedServerFingerprint: fingerprint,
      );
      final closed = session.events.firstWhere((e) => e is SessionClosed).timeout(const Duration(seconds: 10));
      await tv.close();
      final event = await closed as SessionClosed;
      expect(event.error, isA<TvConnectionLost>());
      expect(session.isOpen, isFalse);
      tv = await MockTv.start(); // for tearDown
    });

    test('an unreachable TV is reported as such', () async {
      await expectLater(
        RemoteSession.connect(host: '127.0.0.1', port: 1, identity: identity),
        throwsA(isA<TvUnreachable>()),
      );
    });
  }, skip: unavailable, timeout: const Timeout(Duration(minutes: 2)));
}
