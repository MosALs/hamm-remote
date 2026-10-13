import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// A rounded remote key.
class RemoteKey extends StatelessWidget {
  const RemoteKey({
    super.key,
    required this.onPress,
    required this.label,
    this.icon,
    this.text,
    this.size = const Size(64, 64),
    this.color,
    this.foreground,
    this.repeat = false,
    this.shape = BoxShape.circle,
  }) : assert(icon != null || text != null);

  final VoidCallback onPress;
  final String label;
  final IconData? icon;
  final String? text;
  final Size size;
  final Color? color;
  final Color? foreground;
  final bool repeat;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final base = color ?? const Color(0xFF242832);
    final fg = foreground ?? const Color(0xFFE9ECF2);
    return PressTarget(
      onPress: onPress,
      repeat: repeat,
      semanticLabel: label,
      builder: (context, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: size.width,
        height: size.height,
        transform: Matrix4.diagonal3Values(pressed ? 0.94 : 1, pressed ? 0.94 : 1, 1),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          shape: shape,
          borderRadius: shape == BoxShape.rectangle ? BorderRadius.circular(size.height / 2) : null,
          color: pressed ? Color.lerp(base, Colors.white, 0.12) : base,
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, color: fg, size: size.shortestSide * 0.42)
            : Text(
                text!,
                maxLines: 1,
                style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }
}
