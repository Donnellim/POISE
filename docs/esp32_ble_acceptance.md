# ESP32-C3 BLE integration verification

The supplied protocol replaces the previous phone-owned Rev 9 configuration behavior. The app uses FFE0 / FFE1 (notifications) / FFE2 (ASCII writes) exactly as specified. It no longer sends MODE on connection or binary 0x01 calibration commands, and does not guess alternate GATT characteristics.

Connection subscribes to FFE1 before STATE:SYNC. Both a recognized STATE snapshot and a valid CONFIG are required before controls become available. A timeout keeps settings visible and controls disabled, with a retry action. Mode and vibration changes wait for their matching APPLIED response. Failed commands trigger a new snapshot without being reported as successful.

Step 19 Start Session opens the modal and sends CALIBRATION:READY. The app recognizes STATE:CALIBRATION_READY and enables Set Calibration after acknowledgment. Confirm closes the modal and sends CALIBRATE; success requires SESSION:STARTED or STATE:MONITORING. Cancel, outside-tap, and Back dismissals send CALIBRATION:CANCEL and await STATE:IDLE. SESSION:START remains supported by the service for compatibility, but the dashboard modal flow never sends it. No firmware source is included in this repository.

## Automated coverage

`test/rev9_mode_sync_test.dart` now covers the current protocol, replacing obsolete Rev 9 assertions: split state/config responses, retained settings, disabled disconnected controls, matched acknowledgments, missing/malformed synchronization, command timeout and recovery, calibration/monitoring/session messages, unknown ASCII isolation, and restored idle/paused/monitoring/charging/error states. Dashboard tests exercise the actual session controls and notifications. Other affected onboarding, feedback, and dashboard tests use synchronized simulated connections.

Verification on 2026-10-22: static analysis reported no issues; the full suite passed 144 tests with 2 existing skips. After the final disconnect cleanup, all 40 protocol/device/profile tests passed and static analysis remained clean.

## Physical-device checks still required

### Calibration confirmation and guest Bluetooth access

The dashboard asks the user to set neutral posture before each app-started session. While waiting, the firmware's Step 19 READY state should blink yellow without capturing calibration. Confirmation starts the firmware's three-second solid-yellow calibration followed by its white success cue. The app timer stays at zero until monitoring/start acknowledgment. Reconnection to monitoring or paused sessions does not open the modal or reset the elapsed timer.

Use the Step 19 firmware with this flow. Its bench-test build has ENFORCE_VBUS_LOCKOUT=false: the motor can run on USB. Keep the device on the bench for testing and restore ENFORCE_VBUS_LOCKOUT=true in firmware before normal use/charging. The app does not change this firmware flag. Physical LED timing and USB behavior must be verified on hardware.

On a fresh Android installation, enter guest mode and choose No on either Device Check or Device Setup. Confirm the disconnected dashboard appears without a permission prompt. Tap Bluetooth: allow Nearby devices on Android 12+ or Location on older Android versions, then verify discovery and connection. Deny once and verify the permission-specific message and Settings action, then retry. If Android permanently blocks the prompt, enable access in Settings. Test this on a physical phone; widget tests simulate permission decisions.

Automated tests inject notifications and a command writer; they do not verify a physical radio, ESP32 LittleFS, LED timing, or physical button behavior.

1. Connect and inspect BLE traffic: subscribe FFE1, then STATE:SYNC on FFE2; no calibration or session command until requested.
2. Verify the saved mode and vibration values appear and the connected device remains idle with its LED off after its indication.
3. Disconnect; verify values remain visible and mode, vibration and session controls cannot send commands.
4. Reconnect and verify CONFIG restores saved values. Repeat for each mode and vibration preference after APPLIED responses and a power cycle.
5. Tap Start Session: verify CALIBRATION:READY, blinking yellow, and no calibration capture. Cancel: verify CALIBRATION:CANCEL and LED off. Open again and press Set Calibration: verify CALIBRATE, approximately three seconds solid yellow, white success cue, and monitoring/timer only after firmware confirmation.
6. Pause, resume and end; verify each transition follows device messages.
7. Drop the connection during monitoring and during a pending command. Verify unavailable status, disabled controls and no false command success.
8. Reconnect while idle, paused and monitoring; verify the corresponding interface.
9. Suppress CONFIG or an APPLIED response; verify timeout errors, disabled controls during synchronization, retained values and recovery via a fresh snapshot.

## Reconnection elapsed-time regression

Every connection subscribes to FFE1 before sending STATE:SYNC on FFE2. The app logs `Subscribed to FFE1 notifications`, `TX FFE2 STATE:SYNC`, and each incoming `RX FFE1 SESSION:SYNC:<id>,ELAPSED_MS:<elapsed>` payload. Each valid session snapshot replaces the dashboard time anchor, including unchanged IDs, unchanged elapsed values, and zero. A repeated SESSION:STARTED does not reset an existing timer. Paused snapshots stay frozen until monitoring resumes.

Start monitoring on the device offline, connect once, then double-click to reopen advertising and short-press to stop advertising and continue offline. Wait at least 30 seconds, reopen advertising, and reconnect. Compare the incoming ELAPSED_MS with the displayed timer (whole seconds). Repeat while paused. If no fresh SESSION:SYNC arrives, inspect the notification subscription and firmware response to STATE:SYNC; if the payload is fresh but the display is stale, inspect dashboard snapshot handling.

Automated regression coverage in `test/rev9_mode_sync_test.dart` exercises both snapshot arrival orders, initial mounting after synchronization, repeated reconnections with the same ID, a 30-second offline interval, duplicate STARTED, repeated elapsed corrections, and paused/resumed timing. The protocol and timer suites pass 23 tests, and `flutter analyze` reports no issues. Physical-device verification remains required; no ESP32 firmware or live radio capture was available for this change.
