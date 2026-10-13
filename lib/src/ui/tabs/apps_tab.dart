import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/remote_controller.dart';
import '../../protocol/keycodes.dart';
import '../text_input_sheet.dart';
import '../theme.dart';
import '../widgets/fit_box.dart';
import '../widgets/press_target.dart';

/// Streaming apps on the TV, typing, and playback keys.
class AppsTab extends StatelessWidget {
  const AppsTab({super.key, required this.controller});

  final RemoteController controller;

  void _key(int code) => controller.press(code);

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> children) => Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 10), Expanded(child: children[i])],
          ],
        );
    Widget icon(String label, IconData icon, int code, {bool repeat = false}) =>
        RemoteKey(label: label, icon: icon, height: 50, repeat: repeat, onPress: () => _key(code));
    Widget tile(TvApp app) => AppTile(app: app, onPress: () => controller.openApp(app));
    return FitBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('OPEN ON THE TV', style: kSectionStyle),
          const SizedBox(height: 8),
          row([tile(TvApp.netflix), tile(TvApp.youtube)]),
          const SizedBox(height: 10),
          row([tile(TvApp.primeVideo), tile(TvApp.shahid)]),
          const SizedBox(height: 18),
          const Text('TYPE ON THE TV', style: kSectionStyle),
          const SizedBox(height: 8),
          _KeyboardRow(onPress: () => unawaited(showTextInputSheet(context, controller))),
          const SizedBox(height: 18),
          const Text('PLAYBACK', style: kSectionStyle),
          const SizedBox(height: 8),
          row([
            icon('Rewind', Icons.fast_rewind_rounded, KeyCode.mediaRewind, repeat: true),
            icon('Play or pause', Icons.play_arrow_rounded, KeyCode.mediaPlayPause),
            icon('Stop', Icons.stop_rounded, KeyCode.mediaStop),
            icon('Fast forward', Icons.fast_forward_rounded, KeyCode.mediaFastForward, repeat: true),
          ]),
          const SizedBox(height: 10),
          row([
            icon('Guide', Icons.view_list_rounded, KeyCode.guide),
            icon('Info', Icons.info_outline_rounded, KeyCode.info),
            icon('Subtitles', Icons.closed_caption_outlined, KeyCode.captions),
            icon('Audio track', Icons.audiotrack_rounded, KeyCode.mediaAudioTrack),
          ]),
        ],
      ),
    );
  }
}

/// A coloured tile that opens [app] on the TV.
class AppTile extends StatelessWidget {
  const AppTile({super.key, required this.app, required this.onPress});

  final TvApp app;
  final VoidCallback onPress;

  static (Color, Color, String?) _style(TvApp app) => switch (app) {
        TvApp.netflix => (const Color(0xFFE50914), const Color(0xFF7A0610), null),
        TvApp.youtube => (const Color(0xFFFF3434), const Color(0xFF8F1414), null),
        TvApp.primeVideo => (const Color(0xFF1A98FF), const Color(0xFF0B4A8F), null),
        TvApp.shahid => (const Color(0xFF2BD39A), const Color(0xFF0F6A52), 'شاهد'),
      };

  @override
  Widget build(BuildContext context) {
    final (top, bottom, subtitle) = _style(app);
    return PressTarget(
      onPress: onPress,
      semanticLabel: 'Open ${app.label} on the TV',
      builder: (context, pressed) => AnimatedScale(
        scale: pressed ? 0.97 : 1,
        duration: const Duration(milliseconds: 90),
        child: Container(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [top, bottom]),
            border: Border.all(color: const Color(0x1FFFFFFF)),
            boxShadow: [BoxShadow(color: bottom.withValues(alpha: 0.5), blurRadius: 18, offset: const Offset(0, 8), spreadRadius: -10)],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      app.label.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: Colors.white),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xD9FFFFFF)),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.north_east_rounded, size: 18, color: Color(0xB3FFFFFF)),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyboardRow extends StatelessWidget {
  const _KeyboardRow({required this.onPress});

  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return PressTarget(
      onPress: onPress,
      semanticLabel: 'Type text on the TV',
      builder: (context, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: keyDecoration(pressed: pressed),
        child: const Row(
          children: [
            Icon(Icons.keyboard_rounded, color: Palette.accent, size: 22),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Search or type with your phone',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Palette.text),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Palette.muted),
          ],
        ),
      ),
    );
  }
}
