@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haam_remote/src/app/discovery.dart';
import 'package:haam_remote/src/app/remote_controller.dart';
import 'package:haam_remote/src/app/store.dart';
import 'package:haam_remote/src/crypto/identity.dart';
import 'package:haam_remote/src/protocol/errors.dart';
import 'package:haam_remote/src/protocol/pairing.dart';
import 'package:haam_remote/src/protocol/remote_session.dart';
import 'package:haam_remote/src/ui/connect_screen.dart';
import 'package:haam_remote/src/ui/remote_screen.dart';
import 'package:haam_remote/src/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/test_identity.dart';

// Renders the main screens with real fonts so the UI can be reviewed as
// images. Run with:
//   flutter test --tags screenshots --run-skipped --update-goldens
// The PNGs land in test/screenshots/goldens/.

class _Discovery extends TvDiscovery {
  @override
  List<DiscoveredTv> get tvs => const [DiscoveredTv(name: 'HAAM 55" R4', host: '192.168.1.20', port: 6466)];
  @override
  bool get isRunning => true;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  Future<ByteData> bytes(File f) async => ByteData.sublistView(await f.readAsBytes());
  final roboto = FontLoader('Roboto');
  final icons = FontLoader('MaterialIcons');
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (name.startsWith('Roboto-') && name.endsWith('.ttf')) roboto.addFont(bytes(f));
    if (name.startsWith('MaterialIcons-Regular')) icons.addFont(bytes(f));
  }
  await roboto.load();
  await icons.load();
}

void main() {
  late ClientIdentity identity;

  setUpAll(() async {
    identity = loadTestIdentity();
    await _loadFonts();
  });

  Future<RemoteController> controller({SavedTv? current}) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.open();
    if (current != null) {
      await store.saveTv(current);
      await store.setCurrentTvHost(current.host);
    }
    return RemoteController(
      store: store,
      identity: identity,
      connector: (_, _) => Future<RemoteSession>.error(const TvUnreachable('x')),
      pairingStarter: (_, _) => Future<PairingSession>.error(const TvUnreachable('x')),
    );
  }

  Future<void> shoot(WidgetTester tester, Widget home, String name) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme().copyWith(textTheme: buildTheme().textTheme.apply(fontFamily: 'Roboto')),
      home: home,
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('remote', (tester) async {
    final c = await tester.runAsync(() => controller(
          current: const SavedTv(name: 'Living room', host: '192.168.1.20', serverFingerprint: 'x'),
        ));
    await shoot(tester, RemoteScreen(controller: c!), 'remote');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('connect', (tester) async {
    final c = await tester.runAsync(() => controller());
    final d = _Discovery();
    await shoot(tester, ConnectScreen(controller: c!, discovery: d), 'connect');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    d.dispose();
  });
}
