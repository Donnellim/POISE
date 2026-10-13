# flutter_application_1

A new Flutter project.

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
