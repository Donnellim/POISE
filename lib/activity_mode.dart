import 'package:flutter/material.dart';

/// Mode presets owned by Controls and displayed by the fatigue engine.
enum ActivityMode {
  normal(
    'Normal',
    15,
    2,
    Icons.airline_seat_recline_normal_rounded,
    overlayTitle: 'Normal Mode',
    description:
        'For everyday activities and general posture monitoring. Provides balanced posture monitoring for typical daily activities while allowing normal movements.',
  ),
  focus(
    'Focus',
    10,
    1,
    Icons.menu_book_rounded,
    overlayTitle: 'Focus Mode',
    description:
        'For studying, reading, and other focused academic activities. Uses a more sensitive posture setting to help you stay aware of forward-leaning posture during prolonged study sessions.',
  ),
  gaming(
    'Gaming',
    20,
    3,
    Icons.sports_esports_rounded,
    overlayTitle: 'Gaming Mode',
    description:
        'For gaming and other recreational screen-based activities. Allows more posture movement while still monitoring for sustained forward-leaning posture during longer gaming sessions.',
  ),
  commuting(
    'Commuting',
    25,
    5,
    Icons.directions_subway_rounded,
    overlayTitle: 'Commuting Mode',
    description:
        'For commuting, traveling, and activities involving frequent movement. Uses a more relaxed posture setting to reduce unnecessary feedback caused by normal movements while traveling.',
  );

  const ActivityMode(
    this.label,
    this.angle,
    this.seconds,
    this.icon, {
    required this.overlayTitle,
    required this.description,
  });

  final String label;
  final int angle;
  final int seconds;
  final IconData icon;
  final String overlayTitle;
  final String description;

  /// Backwards-compatibility aliases.
  static const ActivityMode defaultMode = normal;
  static const ActivityMode study = focus;

  String get threshold => '$angle°/${seconds}s';
  int get angleRestriction => angle;
  int get forgivenessTime => seconds;
  String get angleRestrictionDisplay => '$angle°';
  String get forgivenessTimeDisplay => '${seconds}s';
}

