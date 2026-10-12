import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Real-time Spine Tracker Widget
/// Reflects the client's posture angle in real-time.
/// Bends the wireframe torso and animates articulated, glowing vertebrae nodes
/// based on the live pitch angle detected by the P.O.I.S.E. hardware device.
class RealTimeSpineTracker extends StatelessWidget {
  final double pitchAngle; // Degrees (e.g. 18.0)
  final bool isConnected;
  final VoidCallback? onRecalibrateTap;

  const RealTimeSpineTracker({
    super.key,
    required this.pitchAngle,
    required this.isConnected,
    this.onRecalibrateTap,
  });

  @override
  Widget build(BuildContext context) {
    // When disconnected, angle defaults to neutral 0°
    final double currentAngle = isConnected ? pitchAngle : 0.0;

    return SizedBox(
      height: 190,
      width: 200,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // ── Real-Time Articulated Spine & Wireframe Bust ──
          CustomPaint(
            size: const Size(190, 190),
            painter: _SpineTrackerPainter(
              pitchAngle: currentAngle,
              isConnected: isConnected,
            ),
          ),

          // ── Recalibrate Button (Bottom Right) ──
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: onRecalibrateTap,
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.sync_rounded, color: Colors.black87, size: 24),
                  SizedBox(height: 2),
                  Text(
                    'Recalibrate',
                    style: TextStyle(
                      color: Colors.black87,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpineTrackerPainter extends CustomPainter {
  final double pitchAngle;
  final bool isConnected;

  _SpineTrackerPainter({
    required this.pitchAngle,
    required this.isConnected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Base pivot at the lower lumbar spine
    final Offset basePivot = Offset(w * 0.44, h * 0.95);

    // Calculate angular bending
    final double angleRad = (pitchAngle * math.pi / 180.0) * 0.75;

    // Determine status color based on posture severity
    Color spineGlowColor;
    Color tensionColor;
    if (!isConnected) {
      spineGlowColor = const Color(0xFF64B5F6).withValues(alpha: 0.4);
      tensionColor = Colors.white54;
    } else if (pitchAngle.abs() <= 10) {
      spineGlowColor = const Color(0xFF00E676); // Optimal Green
      tensionColor = const Color(0xFF00E5FF);
    } else if (pitchAngle.abs() <= 25) {
      spineGlowColor = const Color(0xFF00E5FF); // Moderate Cyan/Blue
      tensionColor = const Color(0xFF40C4FF);
    } else {
      spineGlowColor = const Color(0xFFFF7043); // High strain Orange/Red
      tensionColor = const Color(0xFFFF5252);
    }

    // ── 1. Draw Holographic Silhouette Mesh (Behind Spine) ──
    _drawSilhouette(canvas, basePivot, angleRad, isConnected);

    // ── 2. Draw Real-Time Dynamic Vertebrae & Spine Cord ──
    _drawVertebraeColumn(
      canvas,
      basePivot,
      angleRad,
      spineGlowColor,
      tensionColor,
    );
  }

  void _drawSilhouette(
    Canvas canvas,
    Offset base,
    double angleRad,
    bool connected,
  ) {
    canvas.save();
    canvas.translate(base.dx, base.dy);
    canvas.rotate(angleRad * 0.6);
    canvas.translate(-base.dx, -base.dy);

    final bodyPaint = Paint()
      ..color = const Color(0xFF08213E).withValues(alpha: 0.88)
      ..style = PaintingStyle.fill;

    final wirePaint = Paint()
      ..color = const Color(0xFF00B0FF).withValues(alpha: connected ? 0.35 : 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final Path bodyPath = Path();
    bodyPath.moveTo(base.dx - 22, base.dy);
    bodyPath.cubicTo(
      base.dx - 28, base.dy - 60,
      base.dx - 22, base.dy - 110,
      base.dx - 12, base.dy - 135,
    );
    bodyPath.cubicTo(
      base.dx - 24, base.dy - 155,
      base.dx - 12, base.dy - 180,
      base.dx + 12, base.dy - 182,
    );
    bodyPath.cubicTo(
      base.dx + 28, base.dy - 182,
      base.dx + 38, base.dy - 172,
      base.dx + 42, base.dy - 158,
    );
    bodyPath.lineTo(base.dx + 42, base.dy - 146);
    bodyPath.lineTo(base.dx + 48, base.dy - 142);
    bodyPath.lineTo(base.dx + 41, base.dy - 138);
    bodyPath.lineTo(base.dx + 42, base.dy - 130);
    bodyPath.lineTo(base.dx + 35, base.dy - 120);
    bodyPath.lineTo(base.dx + 26, base.dy - 105);
    bodyPath.cubicTo(
      base.dx + 36, base.dy - 85,
      base.dx + 44, base.dy - 50,
      base.dx + 38, base.dy,
    );
    bodyPath.close();

    canvas.drawPath(bodyPath, bodyPaint);

    for (double y = base.dy - 170; y <= base.dy - 10; y += 18) {
      canvas.drawLine(
        Offset(base.dx - 26, y),
        Offset(base.dx + 42, y),
        wirePaint,
      );
    }
    for (double x = base.dx - 20; x <= base.dx + 40; x += 16) {
      canvas.drawLine(
        Offset(x, base.dy - 175),
        Offset(x, base.dy),
        wirePaint,
      );
    }

    canvas.restore();
  }

  void _drawVertebraeColumn(
    Canvas canvas,
    Offset base,
    double angleRad,
    Color glowColor,
    Color tensionColor,
  ) {
    const int numVertebrae = 10;
    final List<Offset> points = [];
    const double spineHeight = 145.0;

    for (int i = 0; i < numVertebrae; i++) {
      final double t = i / (numVertebrae - 1);
      final double naturalCurveX = math.sin(t * math.pi * 1.4) * 8.0;
      final double flexShiftX = math.pow(t, 1.4) * (math.tan(angleRad) * 48.0);
      final double flexShiftY = (1.0 - math.cos(angleRad * t)) * 8.0;

      final double px = base.dx - 4 + naturalCurveX + flexShiftX;
      final double py = base.dy - (t * spineHeight) + flexShiftY;

      points.add(Offset(px, py));
    }

    final glowPaint = Paint()
      ..color = glowColor.withValues(alpha: 0.35)
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final linePaint = Paint()
      ..color = tensionColor
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Path spinePath = Path();
    spinePath.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      final p0 = points[i - 1];
      final p1 = points[i];
      final midX = (p0.dx + p1.dx) / 2;
      final midY = (p0.dy + p1.dy) / 2;
      spinePath.quadraticBezierTo(p0.dx, p0.dy, midX, midY);
    }
    spinePath.lineTo(points.last.dx, points.last.dy);

    canvas.drawPath(spinePath, glowPaint);
    canvas.drawPath(spinePath, linePaint);

    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      final bool isCervical = (i >= 7);

      final haloPaint = Paint()
        ..color = glowColor.withValues(alpha: isCervical ? 0.6 : 0.45)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, isCervical ? 5.5 : 4.5, haloPaint);

      final corePaint = Paint()
        ..color = isConnected ? Colors.white : Colors.white70
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, isCervical ? 2.5 : 2.0, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpineTrackerPainter oldDelegate) {
    return oldDelegate.pitchAngle != pitchAngle ||
        oldDelegate.isConnected != isConnected;
  }
}