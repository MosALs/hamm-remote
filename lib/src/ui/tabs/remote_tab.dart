import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/remote_controller.dart';
import '../../protocol/keycodes.dart';
import '../input_sheet.dart';
import '../theme.dart';
import '../widgets/dpad.dart';
import '../widgets/fit_box.dart';
import '../widgets/press_target.dart';
import '../widgets/rocker.dart';

/// Everyday controls: quick keys, D-pad, navigation, volume and channels.
class RemoteTab extends StatelessWidget {
  const RemoteTab({super.key, required this.controller});

  final RemoteController controller;

  void _key(int code) => controller.press(code);

  @override
  Widget build(BuildContext context) {
    Widget quick(String caption, IconData icon, VoidCallback onPress) => Expanded(
          child: RemoteKey(label: caption, icon: icon, caption: caption.toUpperCase(), height: 60, onPress: onPress),
        );
    return FitBox(
      child: Column(
        children: [
          Row(
            children: [
              quick('Input', Icons.input_rounded, () => unawaited(showInputSheet(context, controller))),
              const SizedBox(width: 10),
              quick('Settings', Icons.settings_rounded, () => _key(KeyCode.settings)),
              const SizedBox(width: 10),
              quick('Live TV', Icons.live_tv_rounded, () => _key(KeyCode.tv)),
              const SizedBox(width: 10),
              quick('Mute', Icons.volume_off_rounded, () => _key(KeyCode.volumeMute)),
            ],
          ),
          const SizedBox(height: 18),
          Dpad(
            diameter: 240,
            onPress: (zone) => _key(switch (zone) {
              DpadZone.up => KeyCode.dpadUp,
              DpadZone.down => KeyCode.dpadDown,
              DpadZone.left => KeyCode.dpadLeft,
              DpadZone.right => KeyCode.dpadRight,
              DpadZone.ok => KeyCode.dpadCenter,
            }),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: RemoteKey(label: 'Back', icon: Icons.arrow_back_rounded, height: 50, onPress: () => _key(KeyCode.back)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RemoteKey(
                  label: 'Home',
                  icon: Icons.home_rounded,
                  height: 50,
                  foreground: Palette.accent,
                  tint: const Color(0xFF2B3350),
                  onPress: () => _key(KeyCode.home),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RemoteKey(label: 'Menu', icon: Icons.menu_rounded, height: 50, onPress: () => _key(KeyCode.menu)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Stepper2(
                  label: 'VOL',
                  downIcon: Icons.remove_rounded,
                  upIcon: Icons.add_rounded,
                  downLabel: 'Volume down',
                  upLabel: 'Volume up',
                  onDown: () => _key(KeyCode.volumeDown),
                  onUp: () => _key(KeyCode.volumeUp),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Stepper2(
                  label: 'CH',
                  downIcon: Icons.keyboard_arrow_down_rounded,
                  upIcon: Icons.keyboard_arrow_up_rounded,
                  downLabel: 'Channel down',
                  upLabel: 'Channel up',
                  onDown: () => _key(KeyCode.channelDown),
                  onUp: () => _key(KeyCode.channelUp),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
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
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ColorBar(color: color, label: label, onPress: () => _key(code)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A thin coloured key with a tall touch area.
class ColorBar extends StatelessWidget {
  const ColorBar({super.key, required this.color, required this.label, required this.onPress});

  final Color color;
  final String label;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    return PressTarget(
      onPress: onPress,
      semanticLabel: '$label key',
      builder: (context, pressed) => SizedBox(
        height: 36,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            height: pressed ? 10 : 12,
            decoration: BoxDecoration(
              color: pressed ? Color.lerp(color, Colors.white, 0.3) : color,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 12, spreadRadius: -4)],
            ),
          ),
        ),
      ),
    );
  }
}
