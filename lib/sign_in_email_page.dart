import 'package:flutter/material.dart';
import 'widgets/gradient_background.dart';
import 'device_check_page.dart';

class SignInEmailPage extends StatefulWidget {
  const SignInEmailPage({super.key});

  @override
  State<SignInEmailPage> createState() => _SignInEmailPageState();
}

class _SignInEmailPageState extends State<SignInEmailPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double effectiveWidth =
        screenSize.width > 500 ? 500 : screenSize.width;
    final double buttonWidth = effectiveWidth * 0.8;

    return GradientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // ── Back Button ──
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),

              // ── Top Section: Logo + Title ──
              Expanded(
                flex: 3,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/P.O.I.S.E. Logo 1.png',
                        width: effectiveWidth * 0.35,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'P.O.I.S.E.',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: effectiveWidth * 0.1,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Bottom Sheet Card ──
              Expanded(
                flex: 5,
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Color(0xFFD6EAF8),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(28),
                      topRight: Radius.circular(28),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        // ── Handle Bar ──
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Title ──
                        Text(
                          'Sign In',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: effectiveWidth * 0.065,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // ── Email Field ──
                        SizedBox(
                          width: buttonWidth,
                          child: TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: Colors.black),
                            decoration: InputDecoration(
                              hintText: 'Email',
                              hintStyle: TextStyle(
                                color: Colors.black.withValues(alpha: 0.4),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFB2EBF2),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
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
                                    color: Colors.blue, width: 1.5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // ── Password Field ──
                        SizedBox(
                          width: buttonWidth,
                          child: TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: const TextStyle(color: Colors.black),
                            decoration: InputDecoration(
                              hintText: 'Password',
                              hintStyle: TextStyle(
                                color: Colors.black.withValues(alpha: 0.4),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFB2EBF2),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
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
                                    color: Colors.blue, width: 1.5),
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.black54,
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() =>
                                      _obscurePassword = !_obscurePassword);
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Sign In Button ──
                        SizedBox(
                          width: buttonWidth,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () {
                              // Navigate to device setup flow
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(
                                  builder: (_) => const DeviceCheckPage(),
                                ),
                                (route) => false,
                              );
                            },
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
                              'Sign In',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Remember Me / Forgot Password ──
                        SizedBox(
                          width: buttonWidth,
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              // Remember me
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: Checkbox(
                                      value: _rememberMe,
                                      onChanged: (value) {
                                        setState(
                                            () => _rememberMe = value ?? false);
                                      },
                                      activeColor: Colors.blue,
                                      side: BorderSide(
                                        color:
                                            Colors.black.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Remember me',
                                    style: TextStyle(
                                      color:
                                          Colors.black.withValues(alpha: 0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              // Forgot password
                              GestureDetector(
                                onTap: () {
                                  // TODO: Handle forgot password
                                  debugPrint('Forgot password tapped');
                                },
                                child: Text(
                                  'Forgot password?',
                                  style: TextStyle(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
