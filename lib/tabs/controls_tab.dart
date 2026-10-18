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
    _vibrationEnabled = widget.vibrationEnabled ?? true;
    _notificationEnabled = widget.phoneNotificationEnabled ?? false;
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
              color: const Color(0xFF45A6B8),
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
                            });
                            widget.onRequestNotificationPermission?.call();
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
                                  bottom: 12,
                                  left: 16,
                                  right: 16,
                                ),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF388AF6),
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
                            backgroundColor: const Color(0xFF1E1E1E),
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

  void _onVibrationToggled(bool value) {
    setState(() => _vibrationEnabled = value);
    widget.onVibrationChanged?.call(value);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(value
          ? 'Device vibration feedback enabled.'
          : 'Device vibration feedback disabled.'),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      duration: const Duration(seconds: 2),
    ));
  }

  void _onPhoneNotificationToggled(bool value) {
    if (value && !_notificationPermissionGranted) {
      _showNotificationPermissionDialog();
      return;
    }
    setState(() => _notificationEnabled = value);
    widget.onPhoneNotificationChanged?.call(value);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(
      content: Text(value
          ? 'Phone notification feedback enabled.'
          : 'Phone notification feedback disabled.'),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 76),
        child: SingleChildScrollView(
          key: const PageStorageKey('controls-scroll'),
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
          child: _buildControlsContent(context),
        ),
      ),
    );
  }

  Widget _buildControlsContent(BuildContext context) {
    final mode = widget.selectedMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const PoiseHeader(),
        const SizedBox(height: 10),
        const Text(
          'Controls',
          style: TextStyle(
            color: Color(0xFF0F1E29),
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),

        // ── 1. Activity Mode Container ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFA2DDF0),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Activity Mode',
                style: TextStyle(
                  color: Color(0xFF0F1E29),
                  fontSize: 16.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Select the mode based on what you are currently doing.',
                style: TextStyle(
                  color: Color(0xFF273E4D),
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _ModeCard(
                      icon: ActivityMode.normal.icon,
                      title: ActivityMode.normal.label,
                      subtitle: ActivityMode.normal.threshold,
                      isSelected: widget.selectedMode == ActivityMode.normal,
                      onTap: () => widget.onModeChanged(ActivityMode.normal),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ModeCard(
                      icon: ActivityMode.focus.icon,
                      title: ActivityMode.focus.label,
                      subtitle: ActivityMode.focus.threshold,
                      isSelected: widget.selectedMode == ActivityMode.focus,
                      onTap: () => widget.onModeChanged(ActivityMode.focus),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _ModeCard(
                      icon: ActivityMode.leisure.icon,
                      title: ActivityMode.leisure.label,
                      subtitle: ActivityMode.leisure.threshold,
                      isSelected: widget.selectedMode == ActivityMode.leisure,
                      onTap: () => widget.onModeChanged(ActivityMode.leisure),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ModeCard(
                      icon: ActivityMode.commuting.icon,
                      title: ActivityMode.commuting.label,
                      subtitle: ActivityMode.commuting.threshold,
                      isSelected: widget.selectedMode == ActivityMode.commuting,
                      onTap: () => widget.onModeChanged(ActivityMode.commuting),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── 2. Mode Description Container (Dedicated Section) ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFA2DDF0),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Description',
                style: TextStyle(
                  color: Color(0xFF0F1E29),
                  fontSize: 16.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFBCE7F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  mode.description,
                  style: const TextStyle(
                    color: Color(0xFF273E4D),
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── 3. Feedback Routing Container ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  fontSize: 16.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
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
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Allow your device to vibrate for alerts.',
                            style: TextStyle(
                              color: Color(0xFF334A58),
                              fontSize: 11,
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
                      activeTrackColor: const Color(0xFF388AF6),
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: const Color(0xFF1E1E1E),
                      trackOutlineColor:
                          const WidgetStatePropertyAll(Colors.transparent),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
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
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Allow your device to send notifications.',
                            style: TextStyle(
                              color: Color(0xFF334A58),
                              fontSize: 11,
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
                      activeTrackColor: const Color(0xFF388AF6),
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: const Color(0xFF1E1E1E),
                      trackOutlineColor:
                          const WidgetStatePropertyAll(Colors.transparent),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
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

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 56,
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
              top: 5,
              right: 5,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF388AF6)
                      : const Color(0xFF1E1E1E),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Text(
                    'i',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'serif',
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                  left: 8, right: 20, top: 6, bottom: 6),
              child: Row(
                children: [
                  Icon(icon, color: const Color(0xFF0F1E29), size: 24),
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
