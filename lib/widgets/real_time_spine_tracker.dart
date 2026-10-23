import 'package:flutter/material.dart';

import '../activity_mode.dart';

/// Real-time Static 2D Sagittal Spine Model Tracker
/// Displays the anatomical 2D spine profile (`assets/images/spine_model.png`).
///
/// Warning and slouch alerts are confined strictly to the C7–T1 neck junction
/// and only render when posture deviation exceeds the active mode's thresholds:
/// - Normal: 15° threshold, 2-second forgiveness dwell
/// - Focus: 10° threshold, 1-second forgiveness dwell
/// - Leisure: 20° threshold, 3-second forgiveness dwell
/// - Commuting: 25° threshold, 5-second forgiveness dwell
///
/// In optimal / normal posture, no static marker or badge is placed over the spine,
/// keeping the anatomical spine model clean, natural, and unobstructed.
class RealTimeSpineTracker extends StatelessWidget {
  final double pitchAngle;
  final bool isConnected;
  final ActivityMode activeMode;
  final bool isSlouchAlert;
  final bool isSlouchWarning;
  final VoidCallback? onRecalibrateTap;

  const RealTimeSpineTracker({
    super.key,
    required this.pitchAngle,
    required this.isConnected,
    this.activeMode = ActivityMode.normal,
    this.isSlouchAlert = false,
    this.isSlouchWarning = false,
    this.onRecalibrateTap,
  });

  @override
  Widget build(BuildContext context) {
    final double angle = isConnected ? pitchAngle.abs() : 0.0;
    final double threshold = activeMode.angle.toDouble();

    // Mode-specific threshold and dwell evaluation
    final bool effectiveAlert = isConnected && isSlouchAlert;
    final bool effectiveWarning = isConnected &&
        !effectiveAlert &&
        (isSlouchWarning || angle > threshold);
    final bool effectiveNormal =
        isConnected && !effectiveAlert && !effectiveWarning;

    final Color glowColor = effectiveAlert
        ? const Color(0xFFFF1744) // Exceeded dwell time: Glowing Red
        : effectiveWarning
            ? const Color(0xFFFF9100) // Within dwell time: Glowing Orange
            : const Color(0xFF00E676); // Within threshold: Soft Green

    final String? glowKey = effectiveAlert
        ? 'neck-glow-alert'
        : effectiveWarning
            ? 'neck-glow-warning'
            : (effectiveNormal ? 'neck-glow-optimal' : null);

    return SizedBox(
      width: 220,
      height: 190,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // ── 1. Soft Ambient Halo Behind the Neck (C7–T1 Region) ──
          // Green: Absolute posture deviation is within current mode's threshold.
          // Orange: Deviation exceeds mode threshold, dwell time not yet elapsed.
          // Red: Posture-warning event confirmed after dwell requirement met.
          // Transparent when disconnected.
          if (glowKey != null)
            Positioned(
              left: 78,
              top: 34,
              child: AnimatedContainer(
                key: ValueKey(glowKey),
                duration: const Duration(milliseconds: 250),
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      glowColor.withValues(
                          alpha: effectiveAlert
                              ? 0.90
                              : effectiveWarning
                                  ? 0.75
                                  : 0.50),
                      glowColor.withValues(
                          alpha: effectiveAlert
                              ? 0.45
                              : effectiveWarning
                                  ? 0.30
                                  : 0.15),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),

          // ── 2. Static 2D Anatomical Spine Model Profile ──
          Image.asset(
            'assets/images/spine_model.png',
            height: 190,
            fit: BoxFit.contain,
          ),

          // ── 3. Subtle Neck Surface Illumination (C7–T1) ──
          if (glowKey != null)
            Positioned(
              left: 88,
              top: 44,
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        glowColor.withValues(
                            alpha: effectiveAlert
                                ? 0.55
                                : effectiveWarning
                                    ? 0.40
                                    : 0.25),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}