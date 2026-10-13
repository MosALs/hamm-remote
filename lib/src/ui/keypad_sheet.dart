import 'package:flutter/material.dart';

import '../app/remote_controller.dart';
import '../protocol/keycodes.dart';
import 'theme.dart';
import 'widgets/press_target.dart';

/// Number pad plus the less common keys (guide, info, media).
Future<void> showKeypadSheet(BuildContext context, RemoteController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _KeypadSheet(controller: controller),
  );
}

class _KeypadSheet extends StatelessWidget {
  const _KeypadSheet({required this.controller});

  final RemoteController controller;

  @override
  Widget build(BuildContext context) {
    void key(int code) => controller.press(code);
    Widget digit(int n) => RemoteKey(
          label: '$n',
          text: '$n',
          size: const Size(84, 56),
          shape: BoxShape.rectangle,
          onPress: () => key(KeyCode.digit(n)),
        );
    Widget small(String label, IconData icon, int code) => RemoteKey(
          label: label,
          icon: icon,
          size: const Size(52, 52),
          onPress: () => key(code),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in const [
              [1, 2, 3],
              [4, 5, 6],
              [7, 8, 9],
            ]) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [for (final n in row) digit(n)],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                RemoteKey(
                  label: 'Previous channel',
                  icon: Icons.history_rounded,
                  size: const Size(84, 56),
                  shape: BoxShape.rectangle,
                  onPress: () => key(KeyCode.lastChannel),
                ),
                digit(0),
                RemoteKey(
                  label: 'OK',
                  text: 'OK',
                  size: const Size(84, 56),
                  shape: BoxShape.rectangle,
                  onPress: () => key(KeyCode.dpadCenter),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: Palette.keyBorder, height: 1),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                small('Guide', Icons.view_list_rounded, KeyCode.guide),
                small('Info', Icons.info_outline_rounded, KeyCode.info),
                small('Subtitles', Icons.closed_caption_rounded, KeyCode.captions),
                small('Audio track', Icons.audiotrack_rounded, KeyCode.mediaAudioTrack),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                small('Rewind', Icons.fast_rewind_rounded, KeyCode.mediaRewind),
                small('Play or pause', Icons.play_arrow_rounded, KeyCode.mediaPlayPause),
                small('Stop', Icons.stop_rounded, KeyCode.mediaStop),
                small('Fast forward', Icons.fast_forward_rounded, KeyCode.mediaFastForward),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
