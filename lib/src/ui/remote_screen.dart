import 'dart:async';

import 'package:flutter/material.dart';

import '../app/remote_controller.dart';
import '../protocol/keycodes.dart';
import 'keypad_sheet.dart';
import 'pairing_screen.dart';
import 'text_input_sheet.dart';
import 'theme.dart';
import 'widgets/dpad.dart';
import 'widgets/press_target.dart';
import 'widgets/rocker.dart';

/// The remote itself.
class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key, required this.controller});

  final RemoteController controller;

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  RemoteController get c => widget.controller;
  String? _autoPairedHost;
  bool _pairingOpen = false;

  @override
  void initState() {
    super.initState();
    c.addListener(_maybeAutoPair);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoPair());
  }

  @override
  void dispose() {
    c.removeListener(_maybeAutoPair);
    super.dispose();
  }

  /// Opens pairing by itself the first time a never-paired TV is chosen.
  void _maybeAutoPair() {
    final tv = c.tv;
    if (!mounted || tv == null || tv.isPaired || c.state != LinkState.needsPairing) return;
    if (_autoPairedHost == tv.host) return;
    _autoPairedHost = tv.host;
    unawaited(_openPairing());
  }

  Future<void> _openPairing() async {
    if (_pairingOpen) return;
    _pairingOpen = true;
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => PairingScreen(controller: c),
      ),
    );
    _pairingOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) => Column(
            children: [
              _Header(controller: c, onPair: _openPairing),
              _StatusBanner(controller: c, onPair: _openPairing),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: _RemoteBody.width,
                      height: _RemoteBody.height,
                      child: _RemoteBody(controller: c),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onPair});

  final RemoteController controller;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final tv = controller.tv;
    final (Color dot, String status) = switch (controller.state) {
      LinkState.connected => (Palette.green, 'Connected'),
      LinkState.connecting => (Palette.warning, 'Connecting…'),
      LinkState.offline => (Palette.red, 'Offline'),
      LinkState.needsPairing => (Palette.warning, 'Not paired'),
      LinkState.idle => (Palette.muted, ''),
    };
    final volume = controller.volume;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tv?.name ?? 'TV',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(status, style: const TextStyle(color: Palette.muted, fontSize: 13)),
                    if (volume != null && controller.isConnected) ...[
                      const SizedBox(width: 12),
                      Icon(
                        volume.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        size: 15,
                        color: Palette.muted,
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 64,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: volume.muted ? 0 : volume.fraction,
                            minHeight: 4,
                            backgroundColor: Palette.key,
                            color: Palette.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text('${volume.level}', style: const TextStyle(color: Palette.muted, fontSize: 12)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'TV options',
            onSelected: (value) async {
              switch (value) {
                case 'pair':
                  onPair();
                case 'switch':
                  await controller.switchTv();
                case 'forget':
                  final host = controller.tv?.host;
                  if (host != null) await controller.forgetTv(host);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'pair', child: Text('Pair again')),
              PopupMenuItem(value: 'switch', child: Text('Switch TV')),
              PopupMenuItem(value: 'forget', child: Text('Forget this TV')),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.controller, required this.onPair});

  final RemoteController controller;
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final Widget? content = switch (controller.state) {
      LinkState.needsPairing => _banner(
          icon: Icons.link_rounded,
          text: 'Pair this phone with the TV to start.',
          action: 'Pair',
          onAction: onPair,
        ),
      LinkState.offline => _banner(
          icon: Icons.wifi_off_rounded,
          text: controller.message ?? 'Can\'t reach the TV.',
          action: 'Retry',
          onAction: () => unawaited(controller.connect()),
        ),
      _ => null,
    };
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: content ?? const SizedBox(width: double.infinity),
    );
  }

  Widget _banner({
    required IconData icon,
    required String text,
    required String action,
    required VoidCallback onAction,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.keyBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Palette.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13.5, color: Palette.text)),
          ),
          TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}

/// Fixed-size layout scaled to fit the screen, so nothing scrolls and every
/// key reacts on touch-down.
class _RemoteBody extends StatelessWidget {
  const _RemoteBody({required this.controller});

  static const double width = 360;
  static const double height = 760;

  final RemoteController controller;

  void _key(int code) => controller.press(code);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            RemoteKey(
              label: 'Power',
              icon: Icons.power_settings_new_rounded,
              foreground: Palette.power,
              onPress: () => _key(KeyCode.power),
            ),
            RemoteKey(label: 'Input', icon: Icons.input_rounded, onPress: () => _key(KeyCode.tvInput)),
            RemoteKey(label: 'Settings', icon: Icons.settings_rounded, onPress: () => _key(KeyCode.settings)),
            RemoteKey(label: 'Mute', icon: Icons.volume_off_rounded, onPress: () => _key(KeyCode.volumeMute)),
          ],
        ),
        const SizedBox(height: 20),
        Dpad(
          diameter: 224,
          onPress: (zone) => _key(switch (zone) {
            DpadZone.up => KeyCode.dpadUp,
            DpadZone.down => KeyCode.dpadDown,
            DpadZone.left => KeyCode.dpadLeft,
            DpadZone.right => KeyCode.dpadRight,
            DpadZone.ok => KeyCode.dpadCenter,
          }),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            RemoteKey(label: 'Back', icon: Icons.arrow_back_rounded, onPress: () => _key(KeyCode.back)),
            RemoteKey(
              label: 'Home',
              icon: Icons.home_rounded,
              color: Palette.ring,
              foreground: Palette.ringIcon,
              onPress: () => _key(KeyCode.home),
            ),
            RemoteKey(label: 'Menu', icon: Icons.menu_rounded, onPress: () => _key(KeyCode.menu)),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Rocker(
              label: 'VOL',
              upIcon: Icons.add_rounded,
              downIcon: Icons.remove_rounded,
              upLabel: 'Volume up',
              downLabel: 'Volume down',
              onUp: () => _key(KeyCode.volumeUp),
              onDown: () => _key(KeyCode.volumeDown),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RemoteKey(
                  label: 'Live TV',
                  icon: Icons.live_tv_rounded,
                  size: const Size.square(48),
                  onPress: () => _key(KeyCode.tv),
                ),
                const SizedBox(height: 10),
                RemoteKey(
                  label: 'Number pad',
                  icon: Icons.dialpad_rounded,
                  size: const Size.square(48),
                  onPress: () => unawaited(showKeypadSheet(context, controller)),
                ),
                const SizedBox(height: 10),
                RemoteKey(
                  label: 'Keyboard',
                  icon: Icons.keyboard_rounded,
                  size: const Size.square(48),
                  onPress: () => unawaited(showTextInputSheet(context, controller)),
                ),
              ],
            ),
            Rocker(
              label: 'CH',
              upIcon: Icons.keyboard_arrow_up_rounded,
              downIcon: Icons.keyboard_arrow_down_rounded,
              upLabel: 'Channel up',
              downLabel: 'Channel down',
              onUp: () => _key(KeyCode.channelUp),
              onDown: () => _key(KeyCode.channelDown),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            for (final (color, code, label) in [
              (Palette.red, KeyCode.red, 'Red'),
              (Palette.green, KeyCode.green, 'Green'),
              (Palette.yellow, KeyCode.yellow, 'Yellow'),
              (Palette.blue, KeyCode.blue, 'Blue'),
            ])
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _ColorKey(color: color, label: label, onPress: () => _key(code)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 3.9,
          children: [
            for (final app in TvApp.values)
              _AppKey(app: app, onPress: () => controller.launchApp(app.launchLink)),
          ],
        ),
      ],
    );
  }
}

class _ColorKey extends StatelessWidget {
  const _ColorKey({required this.color, required this.label, required this.onPress});

  final Color color;
  final String label;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return PressTarget(
      onPress: onPress,
      repeat: false,
      semanticLabel: '$label key',
      builder: (context, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        height: 36,
        decoration: BoxDecoration(
          color: pressed ? Color.lerp(color, Colors.white, 0.25) : color,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: pressed ? 0.15 : 0.35), blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
      ),
    );
  }
}

class _AppKey extends StatelessWidget {
  const _AppKey({required this.app, required this.onPress});

  final TvApp app;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final (Color fg, FontWeight weight, double spacing) = switch (app) {
      TvApp.netflix => (const Color(0xFFD81F26), FontWeight.w800, 0.6),
      TvApp.youtube => (const Color(0xFF1B1E25), FontWeight.w700, 0.0),
      TvApp.primeVideo => (const Color(0xFF1B6FB5), FontWeight.w700, 0.0),
      TvApp.shahid => (const Color(0xFF1B1E25), FontWeight.w700, 0.0),
    };
    return PressTarget(
      onPress: onPress,
      semanticLabel: 'Open ${app.label}',
      builder: (context, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        decoration: BoxDecoration(
          color: pressed ? Palette.ringPressed : Palette.ring,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          app == TvApp.netflix ? app.label.toUpperCase() : app.label,
          style: TextStyle(color: fg, fontWeight: weight, fontSize: 16, letterSpacing: spacing),
        ),
      ),
    );
  }
}
