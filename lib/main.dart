import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app/remote_controller.dart';
import 'src/app/store.dart';
import 'src/crypto/identity.dart';
import 'src/ui/connect_screen.dart';
import 'src/ui/remote_screen.dart';
import 'src/ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]));
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Palette.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const HaamRemoteApp());
}

class HaamRemoteApp extends StatefulWidget {
  const HaamRemoteApp({super.key});

  @override
  State<HaamRemoteApp> createState() => _HaamRemoteAppState();
}

class _HaamRemoteAppState extends State<HaamRemoteApp> {
  late Future<RemoteController> _boot = _start();

  /// Loads the saved data and, on first launch, creates the phone's key.
  static Future<RemoteController> _start() async {
    final store = await AppStore.open();
    var identity = store.loadIdentity();
    if (identity == null) {
      identity = await Isolate.run(ClientIdentity.generate);
      await store.saveIdentity(identity);
    }
    return RemoteController(store: store, identity: identity);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HAAM Remote',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      darkTheme: buildTheme(),
      themeMode: ThemeMode.dark,
      home: FutureBuilder<RemoteController>(
        future: _boot,
        builder: (context, snapshot) {
          final controller = snapshot.data;
          if (controller != null) return _Root(controller: controller);
          if (snapshot.hasError) {
            return _Splash(
              message: 'Something went wrong while starting.\n${snapshot.error}',
              onRetry: () => setState(() => _boot = _start()),
            );
          }
          return const _Splash(message: 'Preparing a secure key for pairing…');
        },
      ),
    );
  }
}

/// Shows TV selection until a TV is chosen, then the remote.
class _Root extends StatelessWidget {
  const _Root({required this.controller});

  final RemoteController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: controller.tv == null
            ? ConnectScreen(key: const ValueKey('connect'), controller: controller)
            : RemoteScreen(key: ValueKey(controller.tv!.host), controller: controller),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.settings_remote_rounded, size: 56, color: Palette.accent),
              const SizedBox(height: 20),
              if (onRetry == null) ...[
                const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                const SizedBox(height: 16),
              ],
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Palette.muted)),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                FilledButton(onPressed: onRetry, child: const Text('Try again')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
