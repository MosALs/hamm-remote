import 'package:flutter/material.dart';
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

class FakeDiscovery extends TvDiscovery {
  FakeDiscovery(this._tvs);

  final List<DiscoveredTv> _tvs;

  @override
  List<DiscoveredTv> get tvs => _tvs;

  @override
  bool get isRunning => true;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

Future<RemoteSession> _unreachable(SavedTv tv, ClientIdentity identity) =>
    Future.error(const TvUnreachable('test'));

Future<PairingSession> _pairingUnreachable(SavedTv tv, ClientIdentity identity) =>
    Future.error(const TvUnreachable('test'));

Finder _semantics(String label) =>
    find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label);

const _sizes = [Size(320, 568), Size(360, 640), Size(390, 844), Size(430, 932)];

void main() {
  late ClientIdentity identity;
  setUpAll(() => identity = loadTestIdentity());

  Future<RemoteController> makeController({SavedTv? current}) async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.open();
    if (current != null) {
      await store.saveTv(current);
      await store.setCurrentTvHost(current.host);
    }
    return RemoteController(
      store: store,
      identity: identity,
      connector: _unreachable,
      pairingStarter: _pairingUnreachable,
    );
  }

  Widget app(Widget home, {double textScale = 1}) => MaterialApp(
        theme: buildTheme(),
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: home,
        ),
      );

  for (final size in _sizes) {
    for (final textScale in [1.0, 1.3]) {
      testWidgets('remote fits ${size.width.toInt()}x${size.height.toInt()} at text x$textScale', (tester) async {
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        final controller = await tester.runAsync(() => makeController(
              current: const SavedTv(
                name: 'Living room TV with a rather long name',
                host: '192.168.1.20',
                serverFingerprint: 'pinned',
              ),
            ));
        await tester.pumpWidget(app(RemoteScreen(controller: controller!), textScale: textScale));
        await tester.runAsync(controller.connect);
        await tester.pump();

        expect(find.text('Offline'), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(_semantics('Yellow key'), findsOneWidget);
        expect(find.text('NETFLIX'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      });
    }

    testWidgets('connect screen fits ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final controller = await tester.runAsync(() => makeController());
      final discovery = FakeDiscovery(const [
        DiscoveredTv(name: 'HAAM 55" R4', host: '192.168.1.20', port: 6466),
      ]);
      await tester.pumpWidget(app(ConnectScreen(controller: controller!, discovery: discovery)));
      expect(find.text('Connect to your TV'), findsOneWidget);
      expect(find.text('HAAM 55" R4'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('HAAM 55" R4'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(controller.tv?.host, '192.168.1.20');
      expect(controller.state, LinkState.needsPairing);

      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      discovery.dispose();
    });
  }

  testWidgets('a never-paired TV opens pairing by itself', (tester) async {
    final controller = await tester.runAsync(() => makeController(
          current: const SavedTv(name: 'TV', host: '10.255.255.1'),
        ));
    await tester.runAsync(() => controller!.selectTv(const SavedTv(name: 'TV', host: '10.255.255.1')));
    await tester.pumpWidget(app(RemoteScreen(controller: controller!)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Pair with TV'), findsOneWidget);
    expect(find.text('Pairing didn\'t work'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Pair this phone with the TV to start.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
