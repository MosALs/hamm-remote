import 'package:flutter/material.dart';

import '../../app/remote_controller.dart';
import '../../protocol/keycodes.dart';
import '../theme.dart';
import '../widgets/fit_box.dart';
import '../widgets/press_target.dart';

/// Numbers, sources and the satellite tuning keys.
class KeypadTab extends StatelessWidget {
  const KeypadTab({super.key, required this.controller});

  final RemoteController controller;

  void _key(int code) => controller.press(code);

  @override
  Widget build(BuildContext context) {
    Widget digit(int n) => Expanded(
          child: RemoteKey(label: '$n', text: '$n', textSize: 22, height: 54, onPress: () => _key(KeyCode.digit(n))),
        );
    Widget row(List<Widget> children) => Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 10), children[i]],
          ],
        );
    Widget source(String label, int code) => Expanded(
          child: RemoteKey(label: label, text: label, textSize: 13, height: 42, onPress: () => _key(code)),
        );
    Widget satKey(Color color, String action, int code) => Expanded(
          child: PressTarget(
            onPress: () => _key(code),
            semanticLabel: '$action key',
            builder: (context, pressed) => AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              height: 56,
              decoration: keyDecoration(pressed: pressed),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 22,
                    height: 7,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    action.toUpperCase(),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: Palette.muted),
                  ),
                ],
              ),
            ),
          ),
        );
    return FitBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row([digit(1), digit(2), digit(3)]),
          const SizedBox(height: 10),
          row([digit(4), digit(5), digit(6)]),
          const SizedBox(height: 10),
          row([digit(7), digit(8), digit(9)]),
          const SizedBox(height: 10),
          row([
            Expanded(
              child: RemoteKey(label: 'Last channel', text: 'Last', textSize: 14, height: 54, onPress: () => _key(KeyCode.lastChannel)),
            ),
            digit(0),
            Expanded(
              child: RemoteKey(label: 'OK', text: 'OK', textSize: 15, height: 54, onPress: () => _key(KeyCode.dpadCenter)),
            ),
          ]),
          const SizedBox(height: 18),
          const Text('SOURCES', style: kSectionStyle),
          const SizedBox(height: 8),
          row([
            source('Satellite', KeyCode.tvSatellite),
            source('HDMI 1', KeyCode.tvInputHdmi1),
            source('HDMI 2', KeyCode.tvInputHdmi2),
          ]),
          const SizedBox(height: 8),
          row([
            source('HDMI 3', KeyCode.tvInputHdmi3),
            source('AV', KeyCode.tvInputComposite1),
            source('Antenna', KeyCode.tvTerrestrialDigital),
          ]),
          const SizedBox(height: 18),
          const Text('SATELLITE MENU', style: kSectionStyle),
          const SizedBox(height: 8),
          row([
            satKey(Palette.red, 'Delete', KeyCode.red),
            satKey(Palette.green, 'Edit', KeyCode.green),
            satKey(Palette.yellow, 'Add', KeyCode.yellow),
            satKey(Palette.blue, 'Scan', KeyCode.blue),
          ]),
        ],
      ),
    );
  }
}
