import 'package:flutter/material.dart';

import '../widgets/poise_app_bar.dart';
import '../activity_mode.dart';

class ControlsTab extends StatefulWidget {
  const ControlsTab({
    super.key,
    required this.selectedMode,
    required this.onModeChanged,
    this.vibrationEnabled,
    this.onVibrationChanged,
    this.phoneNotificationEnabled,
    this.onPhoneNotificationChanged,
    this.notificationPermissionGranted,
    this.onRequestNotificationPermission,
  });

  final ActivityMode selectedMode;
  final ValueChanged<ActivityMode> onModeChanged;
  final bool? vibrationEnabled;
  final ValueChanged<bool>? onVibrationChanged;
  final bool? phoneNotificationEnabled;
  final ValueChanged<bool>? onPhoneNotificationChanged;
  final bool? notificationPermissionGranted;
  final VoidCallback? onRequestNotificationPermission;

  @override
  State<ControlsTab> createState() => _ControlsTabState();
}

class _ControlsTabState extends State<ControlsTab> {
  late bool _vibrationEnabled;
  late bool _notificationEnabled;
  late bool _notificationPermissionGranted;

  @override
  void initState() {
    super.initState();
    _vibrationEnabled =
        widget.vibrationEnabled ?? !(widget.phoneNotificationEnabled ?? false);
    _notificationEnabled = !_vibrationEnabled;
    _notificationPermissionGranted =
        widget.notificationPermissionGranted ?? true;
  }

  @override
  void didUpdateWidget(ControlsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.vibrationEnabled != null &&
        widget.vibrationEnabled != oldWidget.vibrationEnabled) {
      _vibrationEnabled = widget.vibrationEnabled!;
    }
    if (widget.phoneNotificationEnabled != null &&
        widget.phoneNotificationEnabled != oldWidget.phoneNotificationEnabled) {
      _notificationEnabled = widget.phoneNotificationEnabled!;
    }
    if (widget.notificationPermissionGranted != null &&
        widget.notificationPermissionGranted !=
            oldWidget.notificationPermissionGranted) {
      _notificationPermissionGranted = widget.notificationPermissionGranted!;
    }
  }

  void _showNotificationPermissionDialog() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 26),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
            decoration: BoxDecoration(
              color: const Color(
                  0xFF45A6B8), // Teal/cyan overlay color matching mockups
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: Color(0xFF0F1E29),
                    size: 34,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Allow Notifications?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF0F1E29),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Phone notifications require notification permission on your device to alert you when posture thresholds are exceeded.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF132F3D),
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            setState(() {
                              _notificationPermissionGranted = true;
                              _notificationEnabled = true;
                              _vibrationEnabled = false;
                            });
                            widget.onRequestNotificationPermission?.call();
                            widget.onVibrationChanged?.call(false);
                            widget.onPhoneNotificationChanged?.call(true);
                            final messenger = ScaffoldMessenger.of(context);
                            messenger.clearSnackBars();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Notification permission granted. Phone notifications enabled.',
                                ),
                                behavior: SnackBarBehavior.floating,
                                margin: EdgeInsets.only(
                                  bottom: 80,
                                  left: 16,
                                  right: 16,
                                ),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF388AF6), // Royal blue button
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                          child: const Text(
                            'Allow',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF1E1E1E), // Dark charcoal button
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                          child: const Text(
                            "Don't Allow",
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _selectFeedback(bool vibration) {
    if (!vibration && !_notificationPermissionGranted) {
      _showNotificationPermissionDialog();
      return;
    }
    setState(() {
      _vibrationEnabled = vibration;
      _notificationEnabled = !vibration;
    });
    widget.onVibrationChanged?.call(vibration);
    widget.onPhoneNotificationChanged?.call(!vibration);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(vibration
          ? 'Phone notification turned off. Device vibration enabled to maintain posture feedback.'
          : 'Device vibration turned off. Phone notification enabled to maintain posture feedback.'),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      duration: const Duration(seconds: 2),
    ));
  }

  void _onVibrationToggled(bool value) => _selectFeedback(value);
  void _onPhoneNotificationToggled(bool value) => _selectFeedback(!value);

  void _showModeOverlay(ActivityMode mode) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 26),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
            decoration: BoxDecoration(
              color: const Color(
                  0xFF45A6B8), // Teal/cyan overlay color matching mockups
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mode.overlayTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF0F1E29),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  mode.description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF132F3D),
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            widget.onModeChanged(mode);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF388AF6), // Royal blue button
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                          child: const Text(
                            'Select',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF1E1E1E), // Dark charcoal button
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding:
              const EdgeInsets.only(left: 14, right: 14, top: 8, bottom: 76),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SizedBox.expand(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: _buildControlsContent(context),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildControlsContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const PoiseHeader(),
        const SizedBox(height: 14),
        const Text(
          'Controls',
          style: TextStyle(
            color: Color(0xFF0F1E29),
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 14),

        // ── Activity Mode Card ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFA2DDF0), // Light sky cyan container
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Activity Mode',
                style: TextStyle(
                  color: Color(0xFF0F1E29),
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Select the mode based on what you are currently doing.',
                style: TextStyle(
                  color: Color(0xFF273E4D),
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _ModeCard(
                      icon: ActivityMode.normal.icon,
                      title: ActivityMode.normal.label,
                      subtitle: ActivityMode.normal.threshold,
                      isSelected: widget.selectedMode == ActivityMode.normal,
                      onTap: () => _showModeOverlay(ActivityMode.normal),
                      onInfoTap: () => _showModeOverlay(ActivityMode.normal),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModeCard(
                      icon: ActivityMode.focus.icon,
                      title: ActivityMode.focus.label,
                      subtitle: ActivityMode.focus.threshold,
                      isSelected: widget.selectedMode == ActivityMode.focus,
                      onTap: () => _showModeOverlay(ActivityMode.focus),
                      onInfoTap: () => _showModeOverlay(ActivityMode.focus),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ModeCard(
                      icon: ActivityMode.leisure.icon,
                      title: ActivityMode.leisure.label,
                      subtitle: ActivityMode.leisure.threshold,
                      isSelected: widget.selectedMode == ActivityMode.leisure,
                      onTap: () => _showModeOverlay(ActivityMode.leisure),
                      onInfoTap: () => _showModeOverlay(ActivityMode.leisure),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ModeCard(
                      icon: ActivityMode.commuting.icon,
                      title: ActivityMode.commuting.label,
                      subtitle: ActivityMode.commuting.threshold,
                      isSelected: widget.selectedMode == ActivityMode.commuting,
                      onTap: () => _showModeOverlay(ActivityMode.commuting),
                      onInfoTap: () => _showModeOverlay(ActivityMode.commuting),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Feedback Routing Card ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFA2DDF0),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Feedback Routing',
                style: TextStyle(
                  color: Color(0xFF0F1E29),
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFBCE7F6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Vibration on Device',
                            style: TextStyle(
                              color: Color(0xFF0F1E29),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Allow your device to vibrate for alerts.',
                            style: TextStyle(
                              color: Color(0xFF334A58),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _vibrationEnabled,
                      onChanged: _onVibrationToggled,
                      thumbIcon: const WidgetStatePropertyAll(Icon(null)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      activeThumbColor: Colors.white,
                      activeTrackColor: const Color(0xFF388AF6), // Blue when ON
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor:
                          const Color(0xFF1E1E1E), // Black when OFF
                      trackOutlineColor:
                          const WidgetStatePropertyAll(Colors.transparent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFBCE7F6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Phone Notification',
                            style: TextStyle(
                              color: Color(0xFF0F1E29),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Silence POISE and receive alerts on your phone.',
                            style: TextStyle(
                              color: Color(0xFF334A58),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _notificationEnabled,
                      onChanged: _onPhoneNotificationToggled,
                      thumbIcon: const WidgetStatePropertyAll(Icon(null)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      activeThumbColor: Colors.white,
                      activeTrackColor: const Color(0xFF388AF6), // Blue when ON
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor:
                          const Color(0xFF1E1E1E), // Black when OFF
                      trackOutlineColor:
                          const WidgetStatePropertyAll(Colors.transparent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Information Callout Banner ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF62C2E8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.info_rounded,
                  color: Color(0xFF208DBA),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Feedback is triggered when an incorrect posture is maintained according to the selected activity mode.',
                  style: TextStyle(
                    color: Color(0xFF0A2230),
                    fontSize: 11.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onInfoTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
    required this.onInfoTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 78,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFD6EEF8) : const Color(0xFFE8ECEF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF388AF6) : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: onInfoTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 17,
                  height: 17,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1E1E1E),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text(
                      'i',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'serif',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: 10, right: 24, top: 10, bottom: 10),
              child: Row(
                children: [
                  Icon(icon, color: const Color(0xFF0F1E29), size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Color(0xFF0F1E29),
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Color(0xFF334A58),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
