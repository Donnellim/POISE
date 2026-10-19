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

    // Mode-specific threshold evaluation
    final bool effectiveAlert =
        isSlouchAlert || (isConnected && angle > threshold + 5.0);
    final bool effectiveWarning = isSlouchWarning ||
        (isConnected && !effectiveAlert && angle > threshold);

    final Color statusColor = effectiveAlert
        ? const Color(0xFFFF1744) // Critical Slouch Alert: Neon Red
        : effectiveWarning
            ? const Color(0xFFFFB300) // Forgiveness Dwell: Vibrant Amber
            : Colors.transparent;

    final String statusLabel = effectiveAlert
        ? 'SLOUCH ALERT'
        : effectiveWarning
            ? 'WARN (${activeMode.seconds}s)'
            : '';

    return SizedBox(
      width: 220,
      height: 190,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          // ── Static 2D Spine Model Image (Side Profile) ──
          Image.asset(
            'assets/images/spine_model.png',
            height: 190,
            fit: BoxFit.contain,
          ),

          // ── C7–T1 Neck Alert / Warning Beacon (Back of Neck) ──
          // Only shown when a warning or alert is triggered for this mode!
          // No static marker or badge is shown during optimal posture.
          if (effectiveAlert || effectiveWarning) ...[
            Positioned(
              left: 98,
              top: 50,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: statusColor.withValues(
                      alpha: effectiveAlert ? 0.45 : 0.28),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: statusColor,
                    width: effectiveAlert ? 2.5 : 1.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(
                          alpha: effectiveAlert ? 0.9 : 0.6),
                      blurRadius: effectiveAlert ? 16 : 10,
                      spreadRadius: effectiveAlert ? 3 : 1.5,
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    effectiveAlert
                        ? Icons.priority_high_rounded
                        : Icons.warning_rounded,
                    color: statusColor,
                    size: effectiveAlert ? 16 : 14,
                  ),
                ),
              ),
            ),

            // ── Mode-Specific Warning / Alert Badge ──
            Positioned(
              left: 126,
              top: 52,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: statusColor, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: statusColor.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}