import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/remote_controller.dart';
import 'keep_awake_screen.dart';
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

final ButtonStyle _secondary = OutlinedButton.styleFrom(
  minimumSize: const Size.fromHeight(50),
  foregroundColor: Palette.accent,
  side: const BorderSide(color: Palette.keyBorder),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
);

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
              'deeply and leaves the Wi-Fi, so the phone can no longer reach it.',
              style: TextStyle(fontSize: 14, height: 1.45, color: Palette.muted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                unawaited(navigator.push(
                  MaterialPageRoute<void>(builder: (_) => KeepAwakeScreen(controller: controller)),
                ));
              },
              icon: const Icon(Icons.wifi_tethering_rounded, size: 20),
              label: const Text('Try keeping the TV reachable when off'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Works on TVs that respect it; some still switch their Wi-Fi off. Other TVs have a setting '
              'instead: Wake on LAN, Network standby or Quick start, under Network or Power. '
              'If neither works, turn the TV on with its own remote.',
              style: TextStyle(fontSize: 13, height: 1.4, color: Palette.muted),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: _secondary,
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(controller.wake());
              },
              icon: const Icon(Icons.power_settings_new_rounded, size: 20),
              label: const Text('Try turning it on'),
            ),
            if (adbOn) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: _secondary,
                onPressed: () {
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  unawaited(showPowerReportSheet(navigator.context, controller));
                },
                icon: const Icon(Icons.fact_check_outlined, size: 20),
                label: const Text('Check the TV (while it is on)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reads the TV's wake-related settings over ADB and shows them, with a
/// button to copy the report so it can be sent for help.
Future<void> showPowerReportSheet(BuildContext context, RemoteController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _PowerReportSheet(report: controller.powerDiagnostics()),
  );
}

class _PowerReportSheet extends StatelessWidget {
  const _PowerReportSheet({required this.report});

  final Future<String> report;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: FutureBuilder<String>(
            future: report,
            builder: (context, snapshot) {
              final text = snapshot.data;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'TV power report',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Palette.text),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Copy it and send it in the chat; it shows which wake settings this TV has.',
                    style: TextStyle(fontSize: 13.5, height: 1.4, color: Palette.muted),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Palette.raised,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Palette.line),
                      ),
                      child: text == null
                          ? const Center(child: CircularProgressIndicator())
                          : SingleChildScrollView(
                              child: SelectableText(
                                text,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11.5,
                                  height: 1.4,
                                  color: Palette.text,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: text == null
                        ? null
                        : () {
                            unawaited(Clipboard.setData(ClipboardData(text: text)));
                            // The sheet would cover a snackbar; close it first.
                            final messenger = ScaffoldMessenger.of(context);
                            Navigator.of(context).pop();
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Report copied. Paste it in the chat.')),
                            );
                          },
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    label: const Text('Copy report'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
