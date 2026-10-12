# Supabase Auth setup (configuration deferred)

Google, Facebook, and Microsoft buttons on both Sign In and Create Account now use Supabase Auth. Firebase and the separate Google/Facebook native SDK dependencies have been removed. No database tables, migrations, profile records, or database queries have been added. Supabase will manage its own authentication users when you configure and use a real project.

## Configure when ready

1. Create or select a Supabase project. Copy its project URL and **publishable key** from the project Connect panel. Never put a secret or service-role key in the app.
2. Enable Google, Facebook, and Azure (Microsoft) in Authentication / Providers. Register an OAuth app with each provider, then put each client ID and secret in the Supabase provider settings. Use the callback URL shown in Supabase, normally `https://<project-ref>.supabase.co/auth/v1/callback`, as the provider's authorized callback URL.
3. For Microsoft, select supported account types including personal Microsoft accounts. Supabase's Azure provider uses the common tenant by default; retain that for personal plus organizational accounts. The app requests the required `email` scope and account selection.
4. Set Authentication / URL Configuration / Site URL to your deployed web app. Add exact allowed redirect URLs for development, production, and mobile:
   - `http://localhost:3000/` for the command below.
   - Your production web app URL, including the correct path and trailing slash.
   - `com.poise.app://login-callback/` for Android and iOS.
5. Copy `config/auth.example.json` to `config/auth.web.local.json`. Fill in `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`; set `SUPABASE_WEB_REDIRECT_URL` for the target web environment.

   ```powershell
   flutter run -d chrome --web-port=3000 --dart-define-from-file=config/auth.web.local.json
   ```

   Android/iOS use the same Supabase project URL/key. Pass a local config file with `--dart-define-from-file` when running on the device. The web redirect setting is ignored on mobile. Android and iOS return-link registrations are already included. If you change the mobile scheme, update `SocialAuth.mobileRedirect`, its callback predicate, Android's manifest, iOS's Info.plist, and the Supabase redirect allowlist together.

Both sign-in and continue buttons launch provider-owned account selection. Web uses a same-tab redirect; mobile opens the system browser and returns via a deep link. The SDK uses PKCE and manages session exchange, persistence, and refresh. A browser opening is never treated as successful authentication. Verified SDK sessions resume the device setup flow, including callbacks that start the app fresh. Profile uses the provider's returned name/email. Logout ends this device's Supabase session.

Missing configuration keeps the prototype usable and displays a setup message on the buttons. The Cancel sign-in button releases the pending UI; it cannot revoke a browser flow already in progress. If the user subsequently finishes that browser flow, its valid callback still signs them in. Returning without completing sign-in allows cancellation or a timeout/retry. Provider denial and callback errors are handled without granting access.

Native Windows/Linux/macOS sign-in callbacks are not configured; use the web build on desktop. Existing email/password screens remain prototype screens; this change concerns the three social providers only. Firebase sessions are not migrated, so previously signed-in users need to sign in again after Supabase configuration.

No passwords or tokens are logged by this app. Supabase's SDK persists its session locally by default; the app's separate feedback preference stores only the selected route.

## Verification after configuration

- Exercise all three providers from both entry screens on Web, Android, and iOS, including a personal Microsoft account.
- Verify provider callback URLs and redirect allowlists with development and release app builds.
- Test cold-start and already-running mobile callbacks, consent denial, cancellation, network failure, and retry.
- Verify the provider name/email, session restoration, logout, and a different account on the next sign-in.
- No real credentials are supplied in this repository; automated tests use synthetic SDK session events and do not sign in to external accounts.

If Flutter on Windows reports missing plugin symlink support, enable Windows Developer Mode and run `flutter pub get` again.

## Notification and feedback scope

The notification popup uses the supplied eight example notices as preview data. Read/clear actions survive tab changes and reopening the popup during the dashboard session. Existing simulated connection changes append notices. Battery/posture events still need real device integration; no notification database or operating-system push delivery has been added. The existing permission UI is an app-level simulation, not a native permission request.

Exactly one feedback route is selected. Choosing phone alerts silences device vibration; choosing vibration disables phone alerts. The route is saved locally across app launches. If the existing app-level notification permission is disabled, vibration remains the fallback until permission is allowed. Changing activity modes, tabs, or reconnecting does not change the selected route.

References: [Supabase Flutter initialization](https://supabase.com/docs/reference/dart/initializing), [OAuth sign-in](https://supabase.com/docs/reference/dart/auth-signinwithoauth), [Microsoft/Azure setup](https://supabase.com/docs/guides/auth/social-login/auth-azure), [Flutter deep links](https://supabase.com/docs/guides/getting-started/tutorials/with-flutter).

## Guest onboarding

Continue as guest opens the same device confirmation, setup, Bluetooth, and calibration walkthrough. A guest choosing No at device confirmation sees a disconnected dashboard with Create Account and Sign In actions. Closing an account screen returns to that prompt; Back to device check lets the guest reconsider device setup.

After social sign-in, or completion of the existing email sign-in/registration prototype, device confirmation runs in account mode. No stays on confirmation with an explanation that a device is required. No at setup returns to confirmation, preserving guest/account mode. Reconfirmation replaces the current route instead of accumulating duplicate pages. Email registration/sign-in remain navigation prototypes, not verified Supabase email sessions.
