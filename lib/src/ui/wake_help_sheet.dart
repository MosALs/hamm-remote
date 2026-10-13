import 'dart:async';

import 'package:flutter/material.dart';

import '../app/remote_controller.dart';
import 'theme.dart';

/// Explains the TV settings that let the phone turn it on after it has been
/// off for a while, with a button to try again.
Future<void> showWakeHelpSheet(BuildContext context, RemoteController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _WakeHelpSheet(controller: controller),
  );
}

class _WakeHelpSheet extends StatelessWidget {
  const _WakeHelpSheet({required this.controller});

  final RemoteController controller;

  @override
  Widget build(BuildContext context) {
    final adbOn = controller.tv?.adbEnabled == true;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Turn the TV on from the phone',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Palette.text),
            ),
            const SizedBox(height: 8),
            const Text(
              'Right after you turn it off, the TV still listens on Wi-Fi. After a few minutes it sleeps '
              'deeply and switches its network off, unless one of its "wake on network" settings is on.',
              style: TextStyle(fontSize: 14, height: 1.45, color: Palette.muted),
            ),
            const SizedBox(height: 16),
            const _Step(
              n: 1,
              title: 'On the TV, open Settings',
              body: 'Look in Network & Internet, and in Device Preferences → Power (or System → Power).',
            ),
            const _Step(
              n: 2,
              title: 'Turn on any of these you find',
              body: 'Wake on LAN · Wake on Wireless LAN (WoWLAN) · Network standby · '
                  'Quick start / Instant power on. Names differ between TV models.',
            ),
            const _Step(
              n: 3,
              title: 'Turn the TV off, wait 10 minutes, try again',
              body: 'If it still sleeps too deeply, a network cable makes waking far more reliable than Wi-Fi.',
            ),
            if (!adbOn)
              const _Step(
                n: 4,
                title: 'Turn on "TV keys over ADB" once',
                body: 'The app then learns the TV\'s Wi-Fi address, which can differ from the one it reports.',
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(controller.wake());
              },
              icon: const Icon(Icons.power_settings_new_rounded, size: 20),
              label: const Text('Try turning it on'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.body});

  final int n;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Palette.accent.withValues(alpha: 0.16), shape: BoxShape.circle),
            child: Text('$n', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Palette.accent)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.text)),
                const SizedBox(height: 3),
                Text(body, style: const TextStyle(fontSize: 13.5, height: 1.4, color: Palette.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
