import 'package:flutter/material.dart';

import '../theme.dart';
import 'press_target.dart';

/// A horizontal two-way key (volume or channel): minus, label, plus.
/// Both ends repeat while held.
class Stepper2 extends StatelessWidget {
  const Stepper2({
    super.key,
    required this.label,
    required this.downIcon,
    required this.upIcon,
    required this.onDown,
    required this.onUp,
    required this.downLabel,
    required this.upLabel,
    this.height = 52,
  });

  final String label;
  final IconData downIcon;
  final IconData upIcon;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final String downLabel;
  final String upLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    Widget end(IconData icon, VoidCallback onPress, String semantic) => SizedBox(
          width: 50,
          child: PressTarget(
            onPress: onPress,
            repeat: true,
            semanticLabel: semantic,
            builder: (context, pressed) => AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              color: pressed ? Palette.raisedHi : Colors.transparent,
              alignment: Alignment.center,
              child: Icon(icon, color: Palette.text, size: 22),
            ),
          ),
        );
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.line),
      ),
      child: Row(
        children: [
          end(downIcon, onDown, downLabel),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Palette.muted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
          ),
          end(upIcon, onUp, upLabel),
        ],
      ),
    );
  }
}
