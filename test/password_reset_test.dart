import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/auth/password_reset.dart';
import 'package:flutter_application_1/forgot_password_page.dart';

class FakeReset implements PasswordResetClient {
  final calls = <String>[];
  bool rejectCode = false;
  bool rejectPassword = false;
  @override
  Future<void> sendCode(String email) async => calls.add('send:$email');
  @override
  Future<void> verifyCode(String email, String code) async {
    calls.add('verify:$email:$code');
    if (rejectCode) throw const AuthException('Code is invalid or expired.');
  }

  @override
  Future<void> resetPassword(String password) async {
    calls.add('reset:$password');
    if (rejectPassword) {
      throw const AuthException('Choose a different password.');
    }
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  Future<void> open(WidgetTester tester, FakeReset client) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
          body: TextButton(
              onPressed: () async {
                final email =
                    await Navigator.of(context).push<String>(MaterialPageRoute(
                  builder: (_) => ForgotPasswordPage(client: client),
                ));
                if (context.mounted && email != null) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Sign in: $email')));
                }
              },
              child: const Text('Forgot password?')));
    })));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.widgetWithText(FilledButton, label));
    await tester.tap(find.widgetWithText(FilledButton, label));
    await tester.pumpAndSettle();
  }

  testWidgets('email, recovery code, matching password, then return to sign in',
      (tester) async {
    final client = FakeReset();
    await open(tester, client);
    await submit(tester, 'Send code');
    expect(client.calls, isEmpty);
    await tester.enterText(
        find.byKey(const ValueKey('reset-email')), 'alex@example.com');
    await submit(tester, 'Send code');
    expect(client.calls, ['send:alex@example.com']);
    await tester.enterText(find.byKey(const ValueKey('reset-code')), '123456');
    client.rejectCode = true;
    await submit(tester, 'Verify code');
    expect(find.text('Code is invalid or expired.'), findsOneWidget);
    expect(find.byKey(const ValueKey('reset-password')), findsNothing);
    client.rejectCode = false;
    await submit(tester, 'Verify code');
    await tester.enterText(
        find.byKey(const ValueKey('reset-password')), 'Newpass123');
    await tester.enterText(
        find.byKey(const ValueKey('reset-confirm')), 'wrong');
    await submit(tester, 'Reset password');
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(client.calls.where((call) => call.startsWith('reset:')), isEmpty);
    await tester.enterText(
        find.byKey(const ValueKey('reset-confirm')), 'Newpass123');
    client.rejectPassword = true;
    await submit(tester, 'Reset password');
    expect(find.text('Choose a different password.'), findsOneWidget);
    client.rejectPassword = false;
    await submit(tester, 'Reset password');
    expect(find.text('Sign in: alex@example.com'), findsOneWidget);
    expect(find.byType(ForgotPasswordPage), findsNothing);
  });

  testWidgets('resend waits for cooldown and sends to the same email',
      (tester) async {
    final client = FakeReset();
    await open(tester, client);
    await tester.enterText(
        find.byKey(const ValueKey('reset-email')), 'alex@example.com');
    await submit(tester, 'Send code');
    expect(
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Resend code in 60s'))
            .onPressed,
        isNull);
    await tester.pump(const Duration(seconds: 60));
    await tester.tap(find.text('Resend code'));
    await tester.pumpAndSettle();
    expect(client.calls, ['send:alex@example.com', 'send:alex@example.com']);
    await tester.pumpWidget(const SizedBox());
  });

  test('cannot update password without a verified recovery session', () async {
    final client = SupabasePasswordReset();
    await expectLater(
        client.resetPassword('Newpass123'), throwsA(isA<AuthException>()));
    await client.dispose();
  });
}
