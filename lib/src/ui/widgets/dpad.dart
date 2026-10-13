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

  double get _okRadius => widget.diameter * 0.23;

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
    final okSize = _okRadius * 2;
    final okPressed = _pressed == DpadZone.ok;
    Widget hidden(String label, DpadZone zone) => Semantics(
          button: true,
          label: label,
          onTap: () => widget.onPress(zone),
          child: const SizedBox.shrink(),
        );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
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
          IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 80),
              width: okSize,
              height: okSize,
              transform: Matrix4.diagonal3Values(okPressed ? 0.95 : 1, okPressed ? 0.95 : 1, 1),
              transformAlignment: Alignment.center,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Palette.accentHi, Palette.accentLo],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Palette.accent.withValues(alpha: okPressed ? 0.25 : 0.55),
                    blurRadius: 26,
                    offset: const Offset(0, 10),
                    spreadRadius: -8,
                  ),
                ],
              ),
              child: const Text(
                'OK',
                style: TextStyle(
                  color: Palette.accentInk,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
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
    final r = size.width / 2 - 1;
    final disc = Rect.fromCircle(center: c, radius: r);

    // Drop shadow, then the disc with a soft top light.
    canvas.drawCircle(
      c.translate(0, 10),
      r - 6,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.3),
          radius: 0.85,
          colors: [Color(0xFF232A3C), Color(0xFF161A26)],
        ).createShader(disc),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Palette.line,
    );

    // Pressed quarter.
    final p = pressed;
    if (p != null && p != DpadZone.ok) {
      final start = switch (p) {
        DpadZone.right => -math.pi / 4,
        DpadZone.down => math.pi / 4,
        DpadZone.left => 3 * math.pi / 4,
        _ => -3 * math.pi / 4,
      };
      final path = Path()
        ..addArc(Rect.fromCircle(center: c, radius: r - 1), start, math.pi / 2)
        ..arcTo(Rect.fromCircle(center: c, radius: okRadius + 4), start + math.pi / 2, -math.pi / 2, false)
        ..close();
      canvas.drawPath(path, Paint()..color = Palette.accent.withValues(alpha: 0.14));
    }

    // Dashed guide ring between the arrows and OK.
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Palette.accent.withValues(alpha: 0.16);
    final ringR = r - 14;
    const dashes = 72;
    for (var i = 0; i < dashes; i += 2) {
      final a = i * 2 * math.pi / dashes;
      canvas.drawArc(Rect.fromCircle(center: c, radius: ringR), a, 2 * math.pi / dashes, false, guide);
    }

    // Arrows.
    final distance = (r + okRadius) / 2 + 2;
    final half = r * 0.07;
    for (final (angle, zone) in [
      (-math.pi / 2, DpadZone.up),
      (math.pi / 2, DpadZone.down),
      (math.pi, DpadZone.left),
      (0.0, DpadZone.right),
    ]) {
      final arrow = Paint()
        ..color = zone == p ? Palette.accent : const Color(0xFFC7CEDE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final tip = c + Offset(math.cos(angle), math.sin(angle)) * (distance + half * 0.6);
      final back = Offset(math.cos(angle), math.sin(angle)) * (half * 1.2);
      final side = Offset(-math.sin(angle), math.cos(angle)) * half * 1.4;
      final path = Path()
        ..moveTo(tip.dx - back.dx + side.dx, tip.dy - back.dy + side.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - back.dx - side.dx, tip.dy - back.dy - side.dy);
      canvas.drawPath(path, arrow);
    }
  }

  @override
  bool shouldRepaint(_DpadPainter old) => old.pressed != pressed || old.okRadius != okRadius;
}
