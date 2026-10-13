import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

enum DpadZone { up, down, left, right, ok }

/// The white directional ring with OK in the middle, like the physical
/// remote. Arrows repeat while held; the touch zone is the whole quarter
/// of the ring, not just the arrow glyph.
class Dpad extends StatefulWidget {
  const Dpad({super.key, required this.onPress, this.diameter = 236});

  final void Function(DpadZone zone) onPress;
  final double diameter;

  @override
  State<Dpad> createState() => _DpadState();
}

class _DpadState extends State<Dpad> {
  DpadZone? _pressed;
  int? _pointer;
  Timer? _delay;
  Timer? _repeat;

  double get _okRadius => widget.diameter * 0.215;

  DpadZone? _zoneAt(Offset local) {
    final r = widget.diameter / 2;
    final d = local - Offset(r, r);
    final distance = d.distance;
    if (distance > r) return null;
    if (distance <= _okRadius) return DpadZone.ok;
    final angle = math.atan2(d.dy, d.dx); // 0 = right, pi/2 = down
    if (angle.abs() <= math.pi / 4) return DpadZone.right;
    if (angle.abs() >= 3 * math.pi / 4) return DpadZone.left;
    return angle > 0 ? DpadZone.down : DpadZone.up;
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    final zone = _zoneAt(e.localPosition);
    if (zone == null) return;
    _pointer = e.pointer;
    setState(() => _pressed = zone);
    unawaited(HapticFeedback.lightImpact());
    widget.onPress(zone);
    if (zone != DpadZone.ok) {
      _delay = Timer(const Duration(milliseconds: 420), () {
        _repeat = Timer.periodic(const Duration(milliseconds: 110), (_) {
          unawaited(HapticFeedback.selectionClick());
          widget.onPress(zone);
        });
      });
    }
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _delay?.cancel();
    _repeat?.cancel();
    setState(() => _pressed = null);
  }

  @override
  void dispose() {
    _delay?.cancel();
    _repeat?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.diameter;
    Widget hidden(String label, DpadZone zone) => Semantics(
          button: true,
          label: label,
          onTap: () => widget.onPress(zone),
          child: const SizedBox.shrink(),
        );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _down,
            onPointerUp: _up,
            onPointerCancel: _up,
            child: CustomPaint(
              size: Size.square(size),
              painter: _DpadPainter(pressed: _pressed, okRadius: _okRadius),
            ),
          ),
          // Accessible labels for screen readers.
          hidden('Up', DpadZone.up),
          hidden('Down', DpadZone.down),
          hidden('Left', DpadZone.left),
          hidden('Right', DpadZone.right),
          hidden('OK', DpadZone.ok),
        ],
      ),
    );
  }
}

class _DpadPainter extends CustomPainter {
  _DpadPainter({required this.pressed, required this.okRadius});

  final DpadZone? pressed;
  final double okRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;

    // Soft shadow under the ring.
    canvas.drawCircle(
      c.translate(0, 3),
      r - 2,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(c, r - 2, Paint()..color = Palette.ring);

    // Highlight the pressed quarter.
    final p = pressed;
    if (p != null && p != DpadZone.ok) {
      final start = switch (p) {
        DpadZone.right => -math.pi / 4,
        DpadZone.down => math.pi / 4,
        DpadZone.left => 3 * math.pi / 4,
        _ => -3 * math.pi / 4,
      };
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..arcTo(Rect.fromCircle(center: c, radius: r - 2), start, math.pi / 2, false)
        ..close();
      canvas.drawPath(path, Paint()..color = Palette.ringPressed);
    }

    // Arrows.
    final arrow = Paint()
      ..color = Palette.ringIcon
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final distance = (r + okRadius) / 2 + 2;
    final half = r * 0.075;
    for (final (angle, zone) in [
      (-math.pi / 2, DpadZone.up),
      (math.pi / 2, DpadZone.down),
      (math.pi, DpadZone.left),
      (0.0, DpadZone.right),
    ]) {
      final tip = c + Offset(math.cos(angle), math.sin(angle)) * (distance + half * 0.6);
      final back = Offset(math.cos(angle), math.sin(angle)) * (half * 1.2);
      final side = Offset(-math.sin(angle), math.cos(angle)) * half * 1.4;
      final path = Path()
        ..moveTo(tip.dx - back.dx + side.dx, tip.dy - back.dy + side.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - back.dx - side.dx, tip.dy - back.dy - side.dy);
      canvas.drawPath(path, arrow..color = zone == p ? Colors.black : Palette.ringIcon);
    }

    // OK key.
    canvas.drawCircle(
      c,
      okRadius,
      Paint()..color = pressed == DpadZone.ok ? const Color(0xFF2B303A) : Palette.okKey,
    );
    final tp = TextPainter(
      text: const TextSpan(
        text: 'OK',
        style: TextStyle(color: Color(0xFFB8BECB), fontSize: 22, fontWeight: FontWeight.w500, letterSpacing: 0.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_DpadPainter old) => old.pressed != pressed || old.okRadius != okRadius;
}
