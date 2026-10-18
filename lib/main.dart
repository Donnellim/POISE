import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'splash_screen.dart';
import 'auth/social_auth.dart';
import 'feedback_preferences.dart';
import 'session_entry_page.dart';
import 'notifications/local_notification_service.dart';
import 'database/local_database.dart';
import 'database/sync_service.dart';

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
  SyncService.instance.initialize();
  try {
    await PoiseLocalDatabase.instance.init();
  } catch (_) {}

  final prefs = await SharedPreferences.getInstance();
  final bool oauthInProgress =
      prefs.getBool('poise.oauth_in_progress') ??  false;
  if (oauthInProgress) {
    await prefs.remove('poise.oauth_in_progress');
  }
  final bool isOAuthReturn = oauthInProgress || SocialAuth.isOAuthRedirect;

  runApp(PoiseApp(isOAuthReturn: isOAuthReturn));
}

class PoiseApp extends StatefulWidget {
  const PoiseApp({super.key, this.isOAuthReturn = false});
  final bool isOAuthReturn;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(LocalNotificationService.instance.ensurePermissionOnAppOpen());
    });
    SocialAuth.instance.lastError.addListener(_showAuthError);
    _authSubscription = SocialAuth.instance.incomingSignIns.listen((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _navigator.currentState?.pushAndRemoveUntil(
          MaterialPageRoute<void>(builder: (_) => const SessionEntryPage()),
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
      home: widget.isOAuthReturn || SocialAuth.isOAuthRedirect
          ? const SessionEntryPage()
          : const SplashScreen(),
    );
  }
}
