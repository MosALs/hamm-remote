import 'package:flutter/material.dart';

import '../theme.dart';
import 'press_target.dart';

/// A vertical two-way key (volume or channel), repeating while held.
class Rocker extends StatelessWidget {
  const Rocker({
    super.key,
    required this.label,
    required this.upIcon,
    required this.downIcon,
    required this.onUp,
    required this.onDown,
    required this.upLabel,
    required this.downLabel,
    this.width = 64,
    this.height = 164,
  });

  final String label;
  final IconData upIcon;
  final IconData downIcon;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final String upLabel;
  final String downLabel;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final radius = Radius.circular(width / 2);
    Widget half(IconData icon, VoidCallback onPress, String semantic, bool top) => Expanded(
          child: PressTarget(
            onPress: onPress,
            repeat: true,
            semanticLabel: semantic,
            builder: (context, pressed) => AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              decoration: BoxDecoration(
                color: pressed ? Palette.keyPressed : Colors.transparent,
                borderRadius: top
                    ? BorderRadius.vertical(top: radius)
                    : BorderRadius.vertical(bottom: radius),
              ),
              alignment: top ? const Alignment(0, -0.35) : const Alignment(0, 0.35),
              child: Icon(icon, color: Palette.text, size: 26),
            ),
          ),
        );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Palette.key,
        borderRadius: BorderRadius.all(radius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            children: [
              half(upIcon, onUp, upLabel, true),
              half(downIcon, onDown, downLabel, false),
            ],
          ),
          IgnorePointer(
            child: Text(
              label,
              style: const TextStyle(
                color: Palette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
