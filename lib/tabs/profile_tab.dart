import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/poise_app_bar.dart';
import '../auth/social_auth.dart';
import '../sign_in_page.dart';

/// Profile tab following the mobile interface v2 design.
class ProfileTab extends StatefulWidget {
  const ProfileTab({
    super.key,
    this.initialUserName = 'User 1',
    this.initialEmail = 'user1@gmail.com',
    this.isBluetoothEnabled,
    this.onBluetoothChanged,
    this.onReconnectSuccess,
    this.bluetoothSearchDuration = const Duration(milliseconds: 1200),
    this.isNotificationPermissionGranted,
    this.onNotificationPermissionChanged,
  });

  final String initialUserName;
  final String initialEmail;
  final bool? isBluetoothEnabled;
  final ValueChanged<bool>? onBluetoothChanged;
  final VoidCallback? onReconnectSuccess;
  final Duration bluetoothSearchDuration;
  final bool? isNotificationPermissionGranted;
  final ValueChanged<bool>? onNotificationPermissionChanged;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  String _firstName = 'User';
  String _lastName = '1';
  String _middleName = '';
  String _email = 'user1@gmail.com';
  String _contactNumber = '';

  bool _bluetoothEnabled = true;
  bool _notificationsEnabled = true;
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    final parts = widget.initialUserName.split(' ');
    _firstName = parts.isNotEmpty ? parts.first : 'User';
    _lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '1';
    _email = widget.initialEmail;
    _bluetoothEnabled = widget.isBluetoothEnabled ?? true;
    _notificationsEnabled = widget.isNotificationPermissionGranted ?? true;
  }

  @override
  void didUpdateWidget(ProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isBluetoothEnabled != null &&
        widget.isBluetoothEnabled != oldWidget.isBluetoothEnabled) {
      setState(() {
        _bluetoothEnabled = widget.isBluetoothEnabled!;
      });
    }
    if (widget.isNotificationPermissionGranted != null &&
        widget.isNotificationPermissionGranted !=
            oldWidget.isNotificationPermissionGranted) {
      setState(() {
        _notificationsEnabled = widget.isNotificationPermissionGranted!;
      });
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  void _openManageAccount() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ManageAccountPage(
          initialFirstName: _firstName,
          initialLastName: _lastName,
          initialMiddleName: _middleName,
          initialEmail: _email,
          initialContactNumber: _contactNumber,
          onSaved: (updated) {
            setState(() {
              _firstName = updated['firstName'] ?? _firstName;
              _lastName = updated['lastName'] ?? _lastName;
              _middleName = updated['middleName'] ?? _middleName;
              _email = updated['email'] ?? _email;
              _contactNumber = updated['contactNumber'] ?? _contactNumber;
            });
          },
        ),
      ),
    );
  }

  void _handleBluetoothToggle(bool value) {
    if (!value) {
      _searchTimer?.cancel();
      setState(() => _bluetoothEnabled = false);
      widget.onBluetoothChanged?.call(false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Bluetooth turned off. P.O.I.S.E. device disconnected.'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      _startBluetoothSearchFlow();
    }
  }

  void _handleNotificationToggle(bool value) {
    setState(() => _notificationsEnabled = value);
    widget.onNotificationPermissionChanged?.call(value);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    if (!value) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Notification permission disabled. Device vibration enabled for feedback.',
          ),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Notification permission granted.'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _startBluetoothSearchFlow() {
    _searchTimer?.cancel();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 26),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: const Color(0xFF45A6B8), // Teal/cyan overlay color
              borderRadius: BorderRadius.circular(24),
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
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: const [
                      SizedBox(
                        width: 58,
                        height: 58,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Color(0xFF0F1E29),
                          ),
                        ),
                      ),
                      Icon(
                        Icons.bluetooth_searching_rounded,
                        color: Color(0xFF0F1E29),
                        size: 32,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Searching for P.O.I.S.E. Device',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF0F1E29),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Searching for POISE-BLE-8492 nearby...\nPlease ensure the device is powered on.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF0F1E29),
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () {
                      _searchTimer?.cancel();
                      Navigator.pop(dialogContext);
                      setState(() => _bluetoothEnabled = false);
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
                      'Cancel',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    _searchTimer = Timer(widget.bluetoothSearchDuration, () {
      if (!mounted) return;
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      setState(() => _bluetoothEnabled = true);
      widget.onBluetoothChanged?.call(true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('P.O.I.S.E. device connected! Recalibrating...'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 80, left: 16, right: 16),
          duration: Duration(seconds: 2),
        ),
      );

      widget.onReconnectSuccess?.call();
    });
  }

  void _showLogoutOverlay(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 26),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: const Color(0xFF45A6B8), // Teal/cyan overlay color
              borderRadius: BorderRadius.circular(24),
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
                const Text(
                  'Log out?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF0F1E29),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Are you sure you would like to log out?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF0F1E29),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(dialogContext);
                            try {
                              await SocialAuth.instance.signOut();
                              if (!context.mounted) return;
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute<void>(
                                    builder: (_) => const SignInPage()),
                                (_) => false,
                              );
                            } catch (_) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Could not log out. Please try again.')),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFFE52222), // Bright red
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                          child: const Text(
                            'Log Out',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF1E1E1E), // Dark charcoal
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 15,
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

  void _showDeleteAccountOverlay(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 26),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
            decoration: BoxDecoration(
              color: const Color(0xFF45A6B8), // Teal/cyan overlay color
              borderRadius: BorderRadius.circular(24),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Delete account',
                  style: TextStyle(
                    color: Color(0xFF0F1E29),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Are you sure you want to delete your account?\nThis action cannot be undone. Please enter your password to confirm.',
                  style: TextStyle(
                    color: Color(0xFF0F1E29),
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2FAEC8),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: const Color(0xFF1E889E), width: 1.2),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  alignment: Alignment.center,
                  child: TextField(
                    obscureText: true,
                    style: const TextStyle(
                      color: Color(0xFF0F1E29),
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Password',
                      hintStyle: TextStyle(
                        color: const Color(0xFF0F1E29).withValues(alpha: 0.55),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Account deleted'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFFE52222), // Bright red
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                          child: const Text(
                            'Delete',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF1E1E1E), // Dark charcoal
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 15,
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

  void _showDeleteDataOverlay(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 26),
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            decoration: BoxDecoration(
              color: const Color(0xFF45A6B8), // Teal/cyan overlay color
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
                const Icon(
                  Icons.warning_rounded,
                  color: Color(0xFFED1C24),
                  size: 68,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Delete all data?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF0F1E29),
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Are you sure you want to delete all your data?\nThis will permanently delete all your saved posture data, records, and history. This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF0F1E29),
                    fontSize: 13,
                    height: 1.45,
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
                            Navigator.pop(dialogContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('All posture data deleted'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFFED1C24), // Bright red
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                          child: const Text(
                            'Delete',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                const Color(0xFF1E1E1E), // Dark charcoal
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 15,
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
    final displayName = '$_firstName $_lastName'.trim().isEmpty
        ? 'User 1'
        : '$_firstName $_lastName'.trim();
    final displayEmail =
        _email.trim().isEmpty ? 'user1@gmail.com' : _email.trim();

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 76),
        child: SingleChildScrollView(
          key: const PageStorageKey('profile-scroll'),
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PoiseHeader(),
              const SizedBox(height: 14),
              const Text(
                'Profile',
                style: TextStyle(
                  color: Color(0xFF0F1E29),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),

              // ── User Card ──
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFA2DDF0),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0xFF19B2E6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              color: Color(0xFF0F1E29),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            displayEmail,
                            style: const TextStyle(
                              color: Color(0xFF334A58),
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ── Manage Account Button ──
              _ProfileRowButton(
                title: 'Manage Account',
                onTap: _openManageAccount,
              ),
              const SizedBox(height: 10),

              // ── Permissions Card ──
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
                      'Permissions',
                      style: TextStyle(
                        color: Color(0xFF0F1E29),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Review and manage app permissions.',
                      style: TextStyle(
                        color: Color(0xFF334A58),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Divider(
                      color: const Color(0xFF6B93A5).withValues(alpha: 0.35),
                      height: 16,
                      thickness: 1,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.bluetooth,
                            color: Color(0xFF0F1E29), size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Bluetooth',
                            style: TextStyle(
                              color: Color(0xFF0F1E29),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Switch(
                          value: _bluetoothEnabled,
                          onChanged: _handleBluetoothToggle,
                          thumbIcon: const WidgetStatePropertyAll(Icon(null)),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          activeThumbColor: Colors.white,
                          activeTrackColor:
                              const Color(0xFF388AF6), // Blue when ON
                          inactiveThumbColor: Colors.white,
                          inactiveTrackColor:
                              const Color(0xFF1E1E1E), // Black when OFF
                          trackOutlineColor:
                              const WidgetStatePropertyAll(Colors.transparent),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.notifications_rounded,
                            color: Color(0xFF0F1E29), size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Notifications',
                            style: TextStyle(
                              color: Color(0xFF0F1E29),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Switch(
                          value: _notificationsEnabled,
                          onChanged: _handleNotificationToggle,
                          thumbIcon: const WidgetStatePropertyAll(Icon(null)),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          activeThumbColor: Colors.white,
                          activeTrackColor:
                              const Color(0xFF388AF6), // Blue when ON
                          inactiveThumbColor: Colors.white,
                          inactiveTrackColor:
                              const Color(0xFF1E1E1E), // Black when OFF
                          trackOutlineColor:
                              const WidgetStatePropertyAll(Colors.transparent),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ── About Card ──
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
                      'About',
                      style: TextStyle(
                        color: Color(0xFF0F1E29),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Divider(
                      color: const Color(0xFF6B93A5).withValues(alpha: 0.35),
                      height: 16,
                      thickness: 1,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'P.O.I.S.E.: Posture-Oriented IoT Sensing Equipment with\n'
                      'Haptic Feedback for Cervicothoracic Orthosis',
                      style: TextStyle(
                        color: Color(0xFF0F1E29),
                        fontSize: 11.5,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text.rich(
                      TextSpan(
                        text: 'Researchers: ',
                        style: TextStyle(
                          color: Color(0xFF0F1E29),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        children: [
                          TextSpan(
                            text: 'BSCpE 4204',
                            style: TextStyle(fontWeight: FontWeight.normal),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text.rich(
                      TextSpan(
                        text: 'Adviser: ',
                        style: TextStyle(
                          color: Color(0xFF0F1E29),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        children: [
                          TextSpan(
                            text: 'Dr. Remedios Ado',
                            style: TextStyle(fontWeight: FontWeight.normal),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Version 1.0.0',
                      style: TextStyle(
                        color: Color(0xFF0F1E29),
                        fontSize: 11,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ── Action Buttons ──
              _ProfileRowButton(
                title: 'Log Out',
                onTap: () => _showLogoutOverlay(context),
              ),
              const SizedBox(height: 10),
              _ProfileRowButton(
                title: 'Delete Account',
                isDestructive: true,
                onTap: () => _showDeleteAccountOverlay(context),
              ),
              const SizedBox(height: 10),
              _ProfileRowButton(
                title: 'Delete All Data',
                isDestructive: true,
                onTap: () => _showDeleteDataOverlay(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable row action button matching the Profile v2 design.
class _ProfileRowButton extends StatelessWidget {
  const _ProfileRowButton({
    required this.title,
    required this.onTap,
    this.isDestructive = false,
  });

  final String title;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final color =
        isDestructive ? const Color(0xFFFF0033) : const Color(0xFF0F1E29);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFA2DDF0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: color,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Manage Account screen featuring contained scroll view and profile edit inputs.
class ManageAccountPage extends StatefulWidget {
  const ManageAccountPage({
    super.key,
    this.initialFirstName = 'User',
    this.initialLastName = '1',
    this.initialMiddleName = '',
    this.initialEmail = 'user1@gmail.com',
    this.initialContactNumber = '',
    this.onSaved,
  });

  final String initialFirstName;
  final String initialLastName;
  final String initialMiddleName;
  final String initialEmail;
  final String initialContactNumber;
  final void Function(Map<String, String> data)? onSaved;

  @override
  State<ManageAccountPage> createState() => _ManageAccountPageState();
}

class _ManageAccountPageState extends State<ManageAccountPage> {
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _middleNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _contactController;
  late final TextEditingController _newPasswordController;
  late final TextEditingController _currentPasswordController;
  late final TextEditingController _confirmPasswordController;

  bool _obscureNewPassword = true;
  bool _obscureCurrentPassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.initialFirstName);
    _lastNameController = TextEditingController(text: widget.initialLastName);
    _middleNameController =
        TextEditingController(text: widget.initialMiddleName);
    _emailController = TextEditingController(text: widget.initialEmail);
    _contactController =
        TextEditingController(text: widget.initialContactNumber);
    _newPasswordController = TextEditingController();
    _currentPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _middleNameController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _newPasswordController.dispose();
    _currentPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _saveChanges() {
    final newPass = _newPasswordController.text;
    final currentPass = _currentPasswordController.text;
    final confirmPass = _confirmPasswordController.text;

    if (newPass.isNotEmpty) {
      if (currentPass.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enter your current password'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (newPass != confirmPass) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New passwords do not match'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      if (newPass.length < 8) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password must be at least 8 characters'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }

    widget.onSaved?.call({
      'firstName': _firstNameController.text.trim(),
      'lastName': _lastNameController.text.trim(),
      'middleName': _middleNameController.text.trim(),
      'email': _emailController.text.trim(),
      'contactNumber': _contactController.text.trim(),
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Changes saved successfully'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );

    Navigator.pop(context);
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF0F1E29),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildCyanInputField({
    required TextEditingController controller,
    String? hintText,
    TextInputType? keyboardType,
  }) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFF50CBE6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A9FB8), width: 1.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(
          color: Color(0xFF0F1E29),
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          hintText: hintText,
          hintStyle: TextStyle(
            color: const Color(0xFF0F1E29).withValues(alpha: 0.4),
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }

  Widget _buildCyanPasswordField({
    required TextEditingController controller,
    required String hintText,
    required bool obscureText,
    required VoidCallback onToggleObscure,
  }) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFF50CBE6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2A9FB8), width: 1.2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscureText,
              style: const TextStyle(
                color: Color(0xFF0F1E29),
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hintText: hintText,
                hintStyle: TextStyle(
                  color: const Color(0xFF0F1E29).withValues(alpha: 0.45),
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: onToggleObscure,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              child: Icon(
                obscureText
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: const Color(0xFF0F1E29).withValues(alpha: 0.65),
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF20A6D7), // Sky Blue Top
              Color(0xFFC3E6EF), // Soft Ice Blue Bottom
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFBCE7F6), // Soft ice blue card
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: SingleChildScrollView(
                      key: const PageStorageKey('manage-account-scroll'),
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Header Row: Back Button + Title ──
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                behavior: HitTestBehavior.opaque,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                      vertical: 4, horizontal: 2),
                                  child: Icon(
                                    Icons.arrow_back_ios_new_rounded,
                                    color: Color(0xFF0F1E29),
                                    size: 20,
                                  ),
                                ),
                              ),
                              const Expanded(
                                child: Center(
                                  child: Text(
                                    'Account',
                                    style: TextStyle(
                                      color: Color(0xFF0F1E29),
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(
                                  width: 22), // Symmetry with back icon
                            ],
                          ),
                          const SizedBox(height: 16),

                          // ── Avatar + Edit Photo ──
                          Center(
                            child: Column(
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF19B2E6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.person,
                                    color: Colors.white,
                                    size: 54,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                            'Photo editing will be available soon'),
                                        behavior: SnackBarBehavior.floating,
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                  child: const Text(
                                    'Edit your photo',
                                    style: TextStyle(
                                      color: Color(0xFF0F1E29),
                                      fontSize: 12,
                                      decoration: TextDecoration.underline,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ── Personal Information ──
                          const Text(
                            'Personal Information',
                            style: TextStyle(
                              color: Color(0xFF0F1E29),
                              fontSize: 16.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildFieldLabel('First Name:'),
                          const SizedBox(height: 4),
                          _buildCyanInputField(
                            controller: _firstNameController,
                            hintText: 'First Name',
                          ),
                          const SizedBox(height: 8),
                          _buildFieldLabel('Last Name:'),
                          const SizedBox(height: 4),
                          _buildCyanInputField(
                            controller: _lastNameController,
                            hintText: 'Last Name',
                          ),
                          const SizedBox(height: 8),
                          _buildFieldLabel('Middle Name:'),
                          const SizedBox(height: 4),
                          _buildCyanInputField(
                            controller: _middleNameController,
                            hintText: 'Middle Name',
                          ),
                          const SizedBox(height: 18),

                          // ── Account Information ──
                          const Text(
                            'Account Information',
                            style: TextStyle(
                              color: Color(0xFF0F1E29),
                              fontSize: 16.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildFieldLabel('E-mail Address:'),
                          const SizedBox(height: 4),
                          _buildCyanInputField(
                            controller: _emailController,
                            hintText: 'E-mail Address',
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 8),
                          _buildFieldLabel('Contact Number:'),
                          const SizedBox(height: 4),
                          _buildCyanInputField(
                            controller: _contactController,
                            hintText: 'Contact Number',
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 18),

                          // ── Change Password ──
                          const Text(
                            'Change Password',
                            style: TextStyle(
                              color: Color(0xFF0F1E29),
                              fontSize: 16.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildCyanPasswordField(
                            controller: _newPasswordController,
                            hintText: 'New Password',
                            obscureText: _obscureNewPassword,
                            onToggleObscure: () => setState(() =>
                                _obscureNewPassword = !_obscureNewPassword),
                          ),
                          const SizedBox(height: 8),
                          _buildCyanPasswordField(
                            controller: _currentPasswordController,
                            hintText: 'Current Password',
                            obscureText: _obscureCurrentPassword,
                            onToggleObscure: () => setState(() =>
                                _obscureCurrentPassword =
                                    !_obscureCurrentPassword),
                          ),
                          const SizedBox(height: 8),
                          _buildCyanPasswordField(
                            controller: _confirmPasswordController,
                            hintText: 'Confirm New Password',
                            obscureText: _obscureConfirmPassword,
                            onToggleObscure: () => setState(() =>
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword),
                          ),
                          const SizedBox(height: 18),

                          // ── Password Requirement Criteria ──
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'New password must contain:',
                                  style: TextStyle(
                                    color: Color(0xFF0F1E29),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 6),
                                _CriteriaRow(text: 'At least 8 characters'),
                                SizedBox(height: 4),
                                _CriteriaRow(
                                    text: 'At least 1 lower letter (a-z)'),
                                SizedBox(height: 4),
                                _CriteriaRow(
                                    text: 'At least 1 upper letter (A-Z)'),
                                SizedBox(height: 4),
                                _CriteriaRow(text: 'At least 1 number (0-9)'),
                                SizedBox(height: 4),
                                _CriteriaRow(
                                    text: 'At least 1 special character'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 22),

                          // ── Save Changes Button ──
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton(
                              onPressed: _saveChanges,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF161616),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Save Changes',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Helper bullet item for password criteria list.
class _CriteriaRow extends StatelessWidget {
  const _CriteriaRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(width: 4),
        Container(
          width: 4.5,
          height: 4.5,
          decoration: const BoxDecoration(
            color: Color(0xFF0F1E29),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF0F1E29),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
