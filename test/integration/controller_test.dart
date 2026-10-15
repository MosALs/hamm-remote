import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:haam_remote/src/adb/adb_client.dart';
import 'package:haam_remote/src/app/remote_controller.dart';
import 'package:haam_remote/src/app/store.dart';
import 'package:haam_remote/src/app/wake_on_lan.dart';
import 'package:haam_remote/src/crypto/identity.dart';
import 'package:haam_remote/src/protocol/keycodes.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/mock_adb.dart';
import '../support/mock_tv.dart';
import '../support/test_identity.dart';

Future<void> waitUntil(bool Function() condition, {Duration timeout = const Duration(seconds: 10)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('Condition not met in $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// The app's controller driving the simulated TV, as a user would:
/// choose the TV, pair, press buttons, lose the connection.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final unavailable = MockTv.unavailableReason();
  if (unavailable != null && Platform.environment['REQUIRE_MOCK_TV'] == '1') {
    throw StateError('Mock TV required in CI but unavailable: $unavailable');
  }

  late ClientIdentity identity;
  setUpAll(() => identity = loadTestIdentity());

  test('choose, pair, control, reconnect', () async {
    SharedPreferences.setMockInitialValues({});
    var tv = await MockTv.start();
    final store = await AppStore.open();
    final controller = RemoteController(store: store, identity: identity);
    addTearDown(controller.dispose);

    await controller.selectTv(SavedTv(
      name: 'Living room',
      host: '127.0.0.1',
      remotePort: tv.remotePort,
      pairingPort: tv.pairPort,
    ));
    expect(controller.state, LinkState.needsPairing);

    // A key pressed before pairing is dropped, not queued forever.
    controller.press(KeyCode.home);

    final pairing = await controller.startPairing();
    final code = (await tv.waitFor('pairing_code'))['code'] as String;
    await controller.finishPairing(pairing, code);
    expect(controller.state, LinkState.connected);
    expect(controller.tv!.isPaired, isTrue);
    expect(store.currentTv!.serverFingerprint, pairing.serverFingerprint);

    controller.press(KeyCode.green);
    controller.press(KeyCode.dpadDown);
    expect((await tv.waitFor('key'))['code'], KeyCode.green);
    expect((await tv.waitFor('key'))['code'], KeyCode.dpadDown);
    expect(tv.events.where((e) => e['event'] == 'key' && e['code'] == KeyCode.home), isEmpty);

    controller.launchApp(TvApp.youtube.launchLink);
    expect((await tv.waitFor('app_link'))['link'], TvApp.youtube.launchLink);
    await waitUntil(() => controller.volume != null);

    // The TV disappears: the controller notices and keeps retrying.
    await tv.close();
    await waitUntil(() => controller.state == LinkState.offline);

    // A different TV now answers on a new port with a new identity:
    // the saved pin forces pairing again instead of silently trusting it.
    tv = await MockTv.start();
    addTearDown(tv.close);
    await controller.selectTv(controller.tv!.copyWith(remotePort: tv.remotePort));
    await waitUntil(() => controller.state == LinkState.needsPairing);
  }, skip: unavailable, timeout: const Timeout(Duration(minutes: 2)));

  test('TV-specific keys and apps go over ADB once it is enabled', () async {
    SharedPreferences.setMockInitialValues({});
    final tv = await MockTv.start();
    addTearDown(tv.close);
    final adb = await MockAdb.start();
    addTearDown(adb.close);
    final store = await AppStore.open();
    final controller = RemoteController(
      store: store,
      identity: identity,
      adbConnector: (_, key, onApproval) =>
          AdbClient.connect(host: '127.0.0.1', port: adb.port, key: key, onApprovalNeeded: onApproval),
    );
    addTearDown(controller.dispose);

    await controller.selectTv(SavedTv(
      name: 'Living room',
      host: '127.0.0.1',
      remotePort: tv.remotePort,
      pairingPort: tv.pairPort,
    ));
    final pairing = await controller.startPairing();
    await controller.finishPairing(pairing, (await tv.waitFor('pairing_code'))['code'] as String);
    expect(controller.tv!.mac, 'AA:BB:CC:DD:EE:0F');

    // Without ADB the key goes over the remote link and the UI is told.
    controller.press(KeyCode.settings);
    expect((await tv.waitFor('key'))['code'], KeyCode.settings);
    expect(controller.adbSuggestions.value, 1);

    var asked = false;
    await controller.enableAdb(onApprovalNeeded: () => asked = true);
    expect(asked, isTrue);
    expect(store.currentTv!.adbEnabled, isTrue);
    // First the app reads the TV's network interfaces (for Wake-on-LAN).
    expect((await adb.waitFor('shell'))['command'], interfaceListCommand);
    expect(store.currentTv!.interfaceMacs, ['AA:BB:CC:DD:EE:0F', 'AA:BB:CC:DD:EE:10']);

    controller.press(KeyCode.tvSatellite);
    expect((await adb.waitFor('shell'))['command'], 'input keyevent ${KeyCode.tvSatellite}');
    controller.press(KeyCode.yellow);
    expect((await adb.waitFor('shell'))['command'], 'input keyevent ${KeyCode.yellow}');
    controller.openApp(TvApp.shahid);
    expect((await adb.waitFor('shell'))['command'], TvApp.shahid.adbLaunchCommand);

    // Ordinary keys still use the remote link.
    controller.press(KeyCode.dpadUp);
    expect((await tv.waitFor('key'))['code'], KeyCode.dpadUp);
    expect(controller.adbError, isNull);
  }, skip: unavailable, timeout: const Timeout(Duration(minutes: 2)));

  test('turns on a TV in deep sleep, using the Wi-Fi MAC learned over ADB', () async {
    SharedPreferences.setMockInitialValues({});
    // Like the user's TV: its Wi-Fi MAC is not the one in its certificate.
    final tv = await MockTv.start(wakeMac: 'AA:BB:CC:DD:EE:10');
    addTearDown(tv.close);
    final adb = await MockAdb.start();
    addTearDown(adb.close);
    final store = await AppStore.open();
    final sent = <List<String>>[];
    final controller = RemoteController(
      store: store,
      identity: identity,
      adbConnector: (_, key, onApproval) =>
          AdbClient.connect(host: '127.0.0.1', port: adb.port, key: key, onApprovalNeeded: onApproval),
      // Real magic packets, sent to the mock instead of the broadcast address.
      wakeSender: (macs, _) {
        sent.add(macs);
        return wakeOnLan(macs, host: '127.0.0.1', ports: [tv.wolPort], broadcast: false);
      },
      wakeWindow: const Duration(seconds: 6),
    );
    addTearDown(controller.dispose);

    await controller.selectTv(SavedTv(
      name: 'Living room',
      host: '127.0.0.1',
      remotePort: tv.remotePort,
      pairingPort: tv.pairPort,
    ));
    final pairing = await controller.startPairing();
    await controller.finishPairing(pairing, (await tv.waitFor('pairing_code'))['code'] as String);
    await waitUntil(() => controller.isConnected);

    // Just turned off: the network is still up, so power goes over the link.
    controller.press(KeyCode.power);
    expect((await tv.waitFor('power'))['on'], isFalse);
    controller.press(KeyCode.power);
    expect((await tv.waitFor('power'))['on'], isTrue);
    controller.press(KeyCode.power);
    expect((await tv.waitFor('power'))['on'], isFalse);

    // Off for a while: deep sleep. The certificate's MAC does not wake it,
    // which is what the user saw.
    await tv.sleep();
    await waitUntil(() => !controller.isConnected);
    expect(await controller.wake(), isTrue);
    expect(controller.wakeFailed, isTrue);
    expect(sent.last, ['AA:BB:CC:DD:EE:0F']);
    expect((await tv.waitFor('wrong_magic_packet'))['mac'], 'AA:BB:CC:DD:EE:0F');
    expect(tv.events.where((e) => e['event'] == 'awake'), isEmpty);

    // With ADB on, the app learns the TV's real interface addresses...
    await controller.enableAdb();
    expect(controller.tv!.interfaceMacs, ['AA:BB:CC:DD:EE:0F', 'AA:BB:CC:DD:EE:10']);
    expect(store.currentTv!.interfaceMacs, ['AA:BB:CC:DD:EE:0F', 'AA:BB:CC:DD:EE:10']);

    // ...and the power button now wakes the network, reconnects, and turns
    // the screen on.
    controller.press(KeyCode.power);
    await tv.waitFor('magic_packet');
    expect((await tv.waitFor('awake'))['screen_on'], isFalse);
    expect((await tv.waitFor('key'))['code'], KeyCode.power);
    expect((await tv.waitFor('power'))['on'], isTrue);
    await waitUntil(() => controller.isConnected && !controller.isWaking);
    expect(controller.wakeFailed, isFalse);
    expect(sent.last, ['AA:BB:CC:DD:EE:0F', 'AA:BB:CC:DD:EE:10']);
  }, skip: unavailable, timeout: const Timeout(Duration(minutes: 2)));

  test('power report reads the TV over ADB', () async {
    SharedPreferences.setMockInitialValues({});
    final adb = await MockAdb.start();
    addTearDown(adb.close);
    final store = await AppStore.open();
    final controller = RemoteController(
      store: store,
      identity: identity,
      connector: (_, _) => Future.error(StateError('no TV in this test')),
      adbConnector: (_, key, onApproval) =>
          AdbClient.connect(host: '127.0.0.1', port: adb.port, key: key, onApprovalNeeded: onApproval),
    );
    addTearDown(controller.dispose);
    await controller.selectTv(const SavedTv(name: 'TV', host: '127.0.0.1', mac: 'AA:BB:CC:DD:EE:0F'));

    final withoutAdb = await controller.powerDiagnostics();
    expect(withoutAdb, contains('Certificate MAC: AA:BB:CC:DD:EE:0F'));
    expect(withoutAdb, contains('ADB is off'));

    await controller.enableAdb();
    final report = await controller.powerDiagnostics();
    expect(report, contains('Interface MACs: AA:BB:CC:DD:EE:0F, AA:BB:CC:DD:EE:10'));
    for (final (title, _) in diagnosticCommands) {
      expect(report, contains('## $title'));
    }
    expect(report, contains('wlan0'));
    expect(report, isNot(contains('(failed')));
  }, skip: unavailable, timeout: const Timeout(Duration(minutes: 1)));
}
