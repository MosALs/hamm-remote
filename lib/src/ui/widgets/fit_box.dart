import 'package:flutter/material.dart';

/// Lays [child] out at a fixed design width and its natural height, then
/// scales it down (never up) to fit the space. Keeps the remote's
/// proportions on every phone without scrolling, so keys can react on
/// touch-down.
class FitBox extends StatelessWidget {
  const FitBox({super.key, required this.child, this.width = 354});

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: SizedBox(width: width, child: child),
      ),
    );
  }
}
