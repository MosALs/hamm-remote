import 'package:flutter/material.dart';

/// Lays [child] out at a fixed design width and its natural height, then
/// scales it down (never up) to fit the space. Keeps the remote's
/// proportions on every phone without scrolling, so keys can react on
/// touch-down.
class FitBox extends StatelessWidget {
  const FitBox({super.key, required this.child, this.width = 354, this.alignment = Alignment.topCenter});

  final Widget child;
  final double width;

  /// Where the content sits when the space is taller than it.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: SizedBox(width: width, child: child),
      ),
    );
  }
}
