# flutter_application_1

A new Flutter project.

## Android APK

Build an installable release APK using the saved local Supabase configuration:

```powershell
flutter build apk --release --dart-define-from-file=config/auth.local.json
```

The APK is generated at `build/app/outputs/flutter-apk/app-release.apk`.
Copy it to an Android phone, open it, and allow installation from that source
if Android prompts you. The launcher name is **P.O.I.S.E.**.

This build currently uses the Android debug signing key for direct testing.
Configure a dedicated release signing key before publishing to Google Play.
Keep `config/auth.local.json` out of version control and include only client-safe
Supabase configuration, never a service-role key.

## Browser demo login

Run `flutter run -d chrome` without `SUPABASE_URL` and
`SUPABASE_PUBLISHABLE_KEY` to test email login without a backend. Choose
**Sign In with Email**, enter a test email such as `tester@example.com` and any
non-empty test password, then press **Sign In**. First-time setup and returning
user routing work as usual. The login form and dashboard label this as a demo.

The demo email is saved only in this browser's local storage until logout;
the password is never stored or sent. This does not create a Supabase account,
send recovery emails, or provide cloud synchronization. Bluetooth in the web
preview remains simulated. Mobile login still requires Supabase.

Supplying either Supabase setting disables demo login, including when the
configuration is incomplete or initialization fails. With both settings supplied,
email login uses real Supabase authentication. Restart the app after changing
these build settings.

## Password recovery setup

Run with the Supabase values from `config/auth.example.json` supplied through
`--dart-define-from-file` using your configured local file. In Supabase Dashboard,
open Authentication > Email Templates > Reset Password and copy
`config/reset_password_email.html` into the email body. The `{{ .Token }}` variable
is required so users receive a code rather than only a reset link. Configure email
delivery/SMTP and the project's OTP expiry and rate limits for production.
See https://supabase.com/docs/guides/auth/auth-email-templates.

Recovery uses Supabase's recovery OTP verification and password update endpoints.
Its temporary session stays in an isolated, non-persisted client so verification
does not sign the user into the app. After saving, users return to email sign-in
and enter their new password. Resending has a 60-second UI cooldown; Supabase
enforces server-side rate limits and expiry. Live email delivery requires a
configured Supabase project and an existing account in Supabase Auth. The current
signup screen is still a prototype and does not create Supabase Auth accounts.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
