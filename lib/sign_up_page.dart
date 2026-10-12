import 'package:flutter/material.dart';
import 'widgets/gradient_background.dart';
import 'device_check_page.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _allowNotifications = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleCreateAccount() {
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => const _RegistrationCompleteDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Column(
                children: [
                  // ── Top Bar: Back Button ──
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back,
                          color: Colors.white, size: 28),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),

                  // ── Top Section: Logo + Title (Scales to prevent overflow) ──
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Image.asset(
                              'assets/images/P.O.I.S.E. Logo 1.png',
                              width: 130,
                              height: 90,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'P.O.I.S.E.',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 40,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ── Bottom Sheet Card ──
                  Expanded(
                    flex: 7,
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Color(0xFFB5E4F5), // Soft sky blue card
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(32),
                          topRight: Radius.circular(32),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // ── Handle Bar ──
                            Container(
                              width: 44,
                              height: 4.5,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(height: 18),

                            // ── Title ──
                            const Text(
                              'Create Account',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 24),

                            // ── Email Field ──
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(
                                  color: Colors.black, fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'Email',
                                hintStyle: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  fontSize: 15,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF52D3E3), // Cyan
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 14,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  borderSide: const BorderSide(
                                      color: Colors.black, width: 1),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF4285F4), width: 1.5),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ── Password Field ──
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              style: const TextStyle(
                                  color: Colors.black, fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'Password',
                                hintStyle: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  fontSize: 15,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF52D3E3),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 14,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  borderSide: const BorderSide(
                                      color: Colors.black, width: 1),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF4285F4), width: 1.5),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.black87,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setState(() =>
                                        _obscurePassword = !_obscurePassword);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ── Confirm Password Field ──
                            TextField(
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirm,
                              style: const TextStyle(
                                  color: Colors.black, fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'Confirm Password',
                                hintStyle: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  fontSize: 15,
                                ),
                                filled: true,
                                fillColor: const Color(0xFF52D3E3),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 14,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  borderSide: const BorderSide(
                                      color: Colors.black, width: 1),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(26),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF4285F4), width: 1.5),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Colors.black87,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setState(() =>
                                        _obscureConfirm = !_obscureConfirm);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // ── Helper Text ──
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: EdgeInsets.only(left: 14),
                                child: Text(
                                  '8+ characters including letters and numbers.',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // ── Notifications Checkbox ──
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Checkbox(
                                    value: _allowNotifications,
                                    onChanged: (value) {
                                      setState(() =>
                                          _allowNotifications = value ?? false);
                                    },
                                    activeColor: const Color(0xFF4285F4),
                                    side: const BorderSide(
                                      color: Colors.black,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Allow notifications to receive alerts and\nupdates.',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      fontSize: 13,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),

                            // ── Create Account Button ──
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: ElevatedButton(
                                onPressed: _handleCreateAccount,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4285F4),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(26),
                                    side: const BorderSide(
                                        color: Colors.black, width: 1),
                                  ),
                                ),
                                child: const Text(
                                  'Create Account',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Registration Complete Overlay Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _RegistrationCompleteDialog extends StatelessWidget {
  const _RegistrationCompleteDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF4DB6AC),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Checkmark Icon ──
            Container(
              width: 70,
              height: 70,
              decoration: const BoxDecoration(
                color: Color(0xFFB2DFDB),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check,
                color: Color(0xFF00796B),
                size: 42,
              ),
            ),
            const SizedBox(height: 24),

            // ── Title (Single Line) ──
            const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Registration Complete!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── Subtitle ──
            const Text(
              'Your account has been successfully created.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 32),

            // ── Continue to Device Check ──
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const DeviceCheckPage(),
                    ),
                    (_) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4285F4),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(26),
                    side: const BorderSide(color: Colors.black, width: 1),
                  ),
                ),
                child: const Text(
                  'Continue to Device Check',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
