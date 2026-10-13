import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/phone_apps.dart';
import '../../app/remote_controller.dart';
import '../theme.dart';
import '../widgets/fit_box.dart';
import '../widgets/press_target.dart';

/// Hooks for tests; the real ones open activities on the phone.
typedef ScreenCastOpener = Future<CastResult> Function();
typedef PhoneAppOpener = Future<bool> Function(CastApp app);

/// Mirrors the phone screen on the TV, or opens a phone app that can cast.
class CastTab extends StatelessWidget {
  const CastTab({
    super.key,
    required this.controller,
    this.screenCastOpener = openScreenCast,
    this.phoneAppOpener = openPhoneApp,
    this.isIos,
  });

  final RemoteController controller;
  final ScreenCastOpener screenCastOpener;
  final PhoneAppOpener phoneAppOpener;

  /// Overrides the platform check (tests).
  final bool? isIos;

  bool get _ios => isIos ?? Platform.isIOS;

  String get _tvName => controller.tv?.name ?? 'your TV';

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _castScreen(BuildContext context) async {
    if (_ios) {
      _snack(context, "iPhone can't mirror to Android TV. Use Cast inside YouTube, Netflix or Shahid instead.");
      return;
    }
    final result = await screenCastOpener();
    if (!context.mounted) return;
    switch (result) {
      case CastResult.opened:
        _snack(context, 'Pick "$_tvName" in the list to show your screen.');
      case CastResult.openedGoogleHome:
        _snack(context, 'In Google Home, open "$_tvName" and tap Cast my screen.');
      case CastResult.unsupported:
        _snack(context, 'Swipe down from the top of your phone and tap Cast or Smart View.');
    }
  }

  Future<void> _openApp(BuildContext context, CastApp app) async {
    final opened = _ios ? false : await phoneAppOpener(app);
    if (!context.mounted || opened) return;
    _snack(context, 'Open ${app.label} on your phone and tap the Cast icon.');
  }

  @override
  Widget build(BuildContext context) {
    return FitBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Hero(tvName: _tvName, onPress: () => unawaited(_castScreen(context))),
          const SizedBox(height: 18),
          const Text('CAST FROM AN APP', style: kSectionStyle),
          const SizedBox(height: 8),
          for (final app in CastApp.values) ...[
            _AppRow(app: app, onPress: () => unawaited(_openApp(context, app))),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          const Text(
            'In the app, tap the Cast icon and pick your TV. The phone stays free while the TV plays.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: Palette.muted),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.tvName, required this.onPress});

  final String tvName;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF242C4A), Color(0xFF151A2A)],
        ),
        border: Border.all(color: const Color(0x268EA2FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0x268EA2FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.cast_rounded, color: Palette.accent, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cast your phone screen',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Palette.text),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Show everything on your phone on $tvName.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, height: 1.35, color: Palette.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPress,
              icon: const Icon(Icons.screen_share_rounded, size: 20),
              label: const Text('Choose what to cast'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({required this.app, required this.onPress});

  final CastApp app;
  final VoidCallback onPress;

  static (IconData, Color) _look(CastApp app) => switch (app) {
        CastApp.youtube => (Icons.smart_display_rounded, const Color(0xFFFF3434)),
        CastApp.netflix => (Icons.movie_rounded, const Color(0xFFE50914)),
        CastApp.photos => (Icons.photo_library_rounded, const Color(0xFF5B8CFF)),
        CastApp.shahid => (Icons.live_tv_rounded, const Color(0xFF2BD39A)),
      };

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _look(app);
    return PressTarget(
      onPress: onPress,
      semanticLabel: 'Open ${app.label} on the phone',
      builder: (context, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: keyDecoration(pressed: pressed, radius: 16),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: color, size: 21),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(app.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.text)),
                  const SizedBox(height: 2),
                  Text(
                    app.hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: Palette.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Palette.muted),
          ],
        ),
      ),
    );
  }
}
