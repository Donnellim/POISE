import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'splash_screen.dart';
import 'auth/social_auth.dart';
import 'feedback_preferences.dart';
import 'device_check_page.dart';
import 'notifications/local_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  await FeedbackPreferences.load();
  await SocialAuth.instance.initialize();
  await LocalNotificationService.instance.initialize();
  runApp(const PoiseApp());
}

class PoiseApp extends StatefulWidget {
  const PoiseApp({super.key});

  @override
  State<PoiseApp> createState() => _PoiseAppState();
}

class _PoiseAppState extends State<PoiseApp> {
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<AuthProfile>? _authSubscription;

  @override
  void initState() {
    super.initState();
    SocialAuth.instance.lastError.addListener(_showAuthError);
    _authSubscription = SocialAuth.instance.incomingSignIns.listen((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _navigator.currentState?.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const DeviceCheckPage()),
          (_) => false,
        );
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }

  void _showAuthError() {
    final message = SocialAuth.instance.lastError.value;
    if (message == null) return;
    _messenger.currentState?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    SocialAuth.instance.lastError.removeListener(_showAuthError);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
      initialRoute: '/',
      title: 'P.O.I.S.E.',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorSchemeSeed: Colors.blue,
      ),
      home: const SplashScreen(),
    );
  }
}
