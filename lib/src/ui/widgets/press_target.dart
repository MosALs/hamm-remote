import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Detects presses with no tap delay and, when [repeat] is set, repeats
/// the action while the finger stays down (for scrolling through lists).
///
/// The remote layout never scrolls, so reacting on pointer-down is safe and
/// makes the buttons feel instant.
class PressTarget extends StatefulWidget {
  const PressTarget({
    super.key,
    required this.onPress,
    required this.builder,
    this.repeat = false,
    this.semanticLabel,
  });

  final VoidCallback onPress;
  final bool repeat;
  final String? semanticLabel;
  final Widget Function(BuildContext context, bool pressed) builder;

  static const Duration repeatDelay = Duration(milliseconds: 420);
  static const Duration repeatInterval = Duration(milliseconds: 110);

  @override
  State<PressTarget> createState() => _PressTargetState();
}

class _PressTargetState extends State<PressTarget> {
  bool _pressed = false;
  Timer? _delay;
  Timer? _repeat;
  int? _pointer;

  void _down(PointerDownEvent event) {
    if (_pointer != null) return;
    _pointer = event.pointer;
    setState(() => _pressed = true);
    unawaited(HapticFeedback.lightImpact());
    widget.onPress();
    if (widget.repeat) {
      _delay = Timer(PressTarget.repeatDelay, () {
        _repeat = Timer.periodic(PressTarget.repeatInterval, (_) {
          unawaited(HapticFeedback.selectionClick());
          widget.onPress();
        });
      });
    }
  }

  void _up(PointerEvent event) {
    if (event.pointer != _pointer) return;
    _stop();
  }

  void _stop() {
    _pointer = null;
    _delay?.cancel();
    _repeat?.cancel();
    _delay = null;
    _repeat = null;
    if (mounted && _pressed) setState(() => _pressed = false);
  }

  @override
  void dispose() {
    _delay?.cancel();
    _repeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      onTap: widget.onPress,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: widget.builder(context, _pressed),
      ),
    );
  }
}

/// A remote key: a raised rounded surface with an icon or text and an
/// optional small caption. It fills the width it is given.
class RemoteKey extends StatelessWidget {
  const RemoteKey({
    super.key,
    required this.onPress,
    required this.label,
    this.icon,
    this.text,
    this.caption,
    this.height = 48,
    this.foreground,
    this.tint,
    this.repeat = false,
    this.radius = 15,
    this.textSize = 16,
  }) : assert(icon != null || text != null);

  final VoidCallback onPress;
  final String label;
  final IconData? icon;
  final String? text;
  final String? caption;
  final double height;
  final Color? foreground;
  final Color? tint;
  final bool repeat;
  final double radius;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? Palette.text;
    return PressTarget(
      onPress: onPress,
      repeat: repeat,
      semanticLabel: label,
      builder: (context, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        height: height,
        transform: Matrix4.diagonal3Values(pressed ? 0.96 : 1, pressed ? 0.96 : 1, 1),
        transformAlignment: Alignment.center,
        decoration: keyDecoration(pressed: pressed, radius: radius, tint: tint),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null)
              Icon(icon, color: fg, size: 22)
            else
              Text(
                text!,
                maxLines: 1,
                style: TextStyle(color: fg, fontSize: textSize, fontWeight: FontWeight.w700),
              ),
            if (caption != null) ...[
              const SizedBox(height: 4),
              Text(
                caption!,
                maxLines: 1,
                style: const TextStyle(
                  color: Palette.muted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
