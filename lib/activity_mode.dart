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
        'Provides balanced posture monitoring for everyday desk work, document drafting, and general computer tasks while allowing natural head movements.',
    intendedActivity:
        'Standard seated desk work, document drafting, general computer tasks, and alternating screen-to-paper reading.',
    monitoringCharacteristics:
        'Balanced sensitivity profile; tolerates natural gaze shifts and functional head articulation between display and desk surfaces while intervening against persistent forward slouching.',
  ),
  focus(
    'Focus',
    10,
    1,
    Icons.menu_book_rounded,
    overlayTitle: 'Focus Mode',
    description:
        'High-sensitivity posture monitoring for intensive desk-bound study sessions and deep focus requiring sustained screen attention.',
    intendedActivity:
        'Disciplined, continuous desk-bound study sessions and intensive technical problem-solving requiring sustained visual attention on monitors or reference texts.',
    monitoringCharacteristics:
        'High-sensitivity profile; strictly enforces neutral cervical alignment to preempt early forward head posture during prolonged static sitting, with a minimal buffer to absorb instantaneous downward glances.',
  ),
  leisure(
    'Leisure',
    20,
    3,
    Icons.weekend_rounded,
    overlayTitle: 'Leisure Mode',
    description:
        'Moderate-tolerance posture monitoring adapted for casual media streaming, handheld gaming, and relaxed seating positions.',
    intendedActivity:
        'Casual media streaming, handheld gaming, and mobile browsing in cushioned, relaxed, or semi-reclined seating configurations.',
    monitoringCharacteristics:
        'Moderate-tolerance profile adapted to non-desk ergonomics; accommodates relaxed spinal inclinations, casual device handling, and minor body shifting without triggering nuisance alerts.',
  ),
  commuting(
    'Commuting',
    25,
    5,
    Icons.directions_subway_rounded,
    overlayTitle: 'Commuting Mode',
    description:
        'Motion-damped posture monitoring for travel and transit, filtering out vehicle vibrations, chassis sway, and road bumps.',
    intendedActivity:
        'Travel via public or private transportation (e.g., jeepneys, buses, trains) and active mobile environments.',
    monitoringCharacteristics:
        'Motion-damped profile; filters out external kinematic disturbances such as chassis vibration, vehicle sway, road bumps, and inertial braking forces to isolate genuine, sustained slumping.',
  );

  const ActivityMode(
    this.label,
    this.angle,
    this.seconds,
    this.icon, {
    required this.overlayTitle,
    required this.description,
    required this.intendedActivity,
    required this.monitoringCharacteristics,
  });

  final String label;
  final int angle;
  final int seconds;
  final IconData icon;
  final String overlayTitle;
  final String description;
  final String intendedActivity;
  final String monitoringCharacteristics;

  /// Backwards-compatibility aliases.
  static const ActivityMode defaultMode = normal;
  static const ActivityMode study = focus;
  static const ActivityMode gaming = leisure;

  String get threshold => '$angle°/${seconds}s';
  int get angleRestriction => angle;
  int get forgivenessTime => seconds;
  String get angleRestrictionDisplay => '$angle°';
  String get forgivenessTimeDisplay => '${seconds}s';
  String get tiltThresholdDisplay => '$angle° forward tilt';
  String get forgivenessDisplay => '$seconds seconds';
}
