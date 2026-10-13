import 'package:flutter/material.dart';

import '../app/remote_controller.dart';
import '../protocol/keycodes.dart';
import 'theme.dart';
import 'widgets/press_target.dart';

/// Picks the TV's source directly. Some TVs ignore the generic "input" key
/// when it arrives over the network, but act on the per-source keys.
Future<void> showInputSheet(BuildContext context, RemoteController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _InputSheet(controller: controller),
  );
}

class _Source {
  const _Source(this.label, this.icon, this.keyCode);

  final String label;
  final IconData icon;
  final int keyCode;
}

const _sources = [
  _Source('Satellite', Icons.satellite_alt_rounded, KeyCode.tvSatellite),
  _Source('HDMI 1', Icons.settings_input_hdmi_rounded, KeyCode.tvInputHdmi1),
  _Source('HDMI 2', Icons.settings_input_hdmi_rounded, KeyCode.tvInputHdmi2),
  _Source('HDMI 3', Icons.settings_input_hdmi_rounded, KeyCode.tvInputHdmi3),
  _Source('AV', Icons.settings_input_composite_rounded, KeyCode.tvInputComposite1),
  _Source('Antenna', Icons.settings_input_antenna_rounded, KeyCode.tvTerrestrialDigital),
];

class _InputSheet extends StatelessWidget {
  const _InputSheet({required this.controller});

  final RemoteController controller;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Input', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Switch the TV straight to a source.',
              style: TextStyle(color: Palette.muted, fontSize: 13.5),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.25,
              children: [
                for (final source in _sources)
                  _SourceTile(
                    source: source,
                    onPress: () {
                      controller.press(source.keyCode);
                      Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                controller.press(KeyCode.tvInput);
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.input_rounded, size: 18),
              label: const Text('Open the TV source menu'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.source, required this.onPress});

  final _Source source;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return PressTarget(
      onPress: onPress,
      semanticLabel: source.label,
      builder: (context, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        decoration: BoxDecoration(
          color: pressed ? Palette.keyPressed : Palette.key,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.keyBorder),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(source.icon, color: Palette.accent, size: 24),
            const SizedBox(height: 8),
            Text(source.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
