import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haam_remote/src/app/discovery.dart';
import 'package:haam_remote/src/app/phone_apps.dart';
import 'package:haam_remote/src/app/remote_controller.dart';
import 'package:haam_remote/src/app/store.dart';
import 'package:haam_remote/src/crypto/identity.dart';
import 'package:haam_remote/src/protocol/errors.dart';
import 'package:haam_remote/src/protocol/pairing.dart';
import 'package:haam_remote/src/protocol/remote_session.dart';
import 'package:haam_remote/src/ui/connect_screen.dart';
import 'package:haam_remote/src/ui/remote_screen.dart';
import 'package:haam_remote/src/ui/tabs/cast_tab.dart';
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

/// Names the widgets behind any overflowing Row/Column, for failure messages.
String _overflows(WidgetTester tester) => [
      for (final ro in tester.allRenderObjects)
        if (ro is RenderFlex && ro.toStringShort().contains('OVERFLOWING')) '${ro.toStringShort()} <- ${ro.debugCreator}',
    ].join('\n');

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
      tvFinder: () async => const [],
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
        expect(find.text('INPUT'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Every tab lays out without overflow at this size.
        for (final (tab, marker) in [
          ('Keypad', 'SATELLITE MENU'),
          ('Apps', 'NETFLIX'),
          ('Cast', 'Cast your phone screen'),
          ('Remote', 'INPUT'),
        ]) {
          await tester.tap(find.text(tab));
          await tester.pump(const Duration(milliseconds: 200));
          expect(find.text(marker), findsOneWidget, reason: '$tab tab');
          expect(tester.takeException(), isNull, reason: '$tab tab\n${_overflows(tester)}');
        }

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

  testWidgets('cast tab opens the phone cast picker and apps', (tester) async {
    final controller = await tester.runAsync(() => makeController(
          current: const SavedTv(name: 'Salon TV', host: '192.168.1.20', serverFingerprint: 'pinned'),
        ));
    var castCalls = 0;
    var result = CastResult.opened;
    final opened = <CastApp>[];
    var appOpens = true;
    await tester.pumpWidget(app(Scaffold(
      body: CastTab(
        controller: controller!,
        isIos: false,
        screenCastOpener: () async {
          castCalls++;
          return result;
        },
        phoneAppOpener: (a) async {
          opened.add(a);
          return appOpens;
        },
      ),
    )));

    await tester.tap(find.text('Choose what to cast'));
    await tester.pump();
    expect(castCalls, 1);
    expect(find.text('Pick "Salon TV" in the list to show your screen.'), findsOneWidget);

    result = CastResult.unsupported;
    await tester.tap(find.text('Choose what to cast'));
    await tester.pump();
    expect(find.text('Swipe down from the top of your phone and tap Cast or Smart View.'), findsOneWidget);

    await tester.tap(find.text('YouTube'));
    await tester.pump();
    expect(opened, [CastApp.youtube]);

    appOpens = false;
    await tester.tap(find.text('Shahid'));
    await tester.pump();
    expect(opened, [CastApp.youtube, CastApp.shahid]);
    expect(find.text('Open Shahid on your phone and tap the Cast icon.'), findsOneWidget);

    await tester.pumpWidget(app(Scaffold(body: CastTab(controller: controller, isIos: true))));
    await tester.tap(find.text('Choose what to cast'));
    await tester.pump();
    expect(find.textContaining("iPhone can't mirror"), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

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
