# Step 21 mobile integration

Implemented against the supplied candidate protocol, not hardware-verified firmware.

## Storage and consent

The existing `posture_events` table requires locally observed sessions. The new SQLite
version 2 migration adds `device_posture_events` without fabricating parent sessions.
It stores the firmware fields and nullable UTC milliseconds, with `(device_id,event_id)`
as its primary key. Duration is derived only when both timestamps exist. Matching
replays are acknowledged after transaction completion; conflicting replays stop import.
Imported history appears separately in Analytics for guests and signed-in users.
It does not contribute invented wear time, session duration, or complete offline sessions
to the legacy live-session charts. Vibration counts describe commanded pulses.

Connection setup subscribes to FFE1, sends current UTC milliseconds on FFE2, obtains
state/config (and a session snapshot when monitoring/paused), then requests outbox status.
A deferred clock permits restoring an existing session but blocks fresh session/calibration
commands until APPLIED/OK. Clock retry and explicit import retry are available on Home.
Import consent is scoped to a connection; disconnect invalidates pending reads/commits
for acknowledgement purposes. A late SQLite commit is safe and deduplicated on retry.
Writes are serialized; response waiters are installed before writes. ACK:FAILED retries
the same committed event up to three times. Read/parse/commit errors never cause ACK.
Mode/session notifications refresh the device snapshot and check the approved outbox.
Mode changes reuse the existing reference and do not launch calibration.

## Supabase deployment

Apply `supabase/migrations/20261023_step21_device_events.sql` to the target project
before cloud testing. This change has not been applied remotely. The table preserves
opaque firmware IDs, uses `(user_id,device_id,event_id)` for cloud idempotency, and has
owner-only insert/select/delete RLS. Conflicting cloud records are not overwritten.

Sign-in offers linking unowned imported history. Analytics also offers a manual sync
button for signed-in users. Approval is remembered per account; unowned imports are
linked only after that approval. Owned rows upload when sync runs or connectivity returns.
Cloud restore pages through event records independently of session history, merging into
SQLite. Cloud failures retain local rows and never prevent or delay device ACKs.
The legacy session/event sync remains separate from the imported-event table.

## Platform findings and required hardware checks

Only Windows and browser targets were detected here; no Android/iOS phone or wearable
was available. Firmware compilation, radio behavior, RLS deployment and live cloud access
have not been verified. Automated tests use simulated FFE1/FFE2/FFE3 plus actual SQLite.

Inspection of installed flutter_blue_plus 2.3.14 shows `read()` uses the platform GATT
read and returns its callback bytes. Android uses `onCharacteristicRead`; Darwin uses
CoreBluetooth `readValueForCharacteristic`. There is no app-level record continuation
API in the documented firmware protocol. Verify complete FFE3 JSON reads at negotiated
MTUs, particularly records larger than one ATT response and near the characteristic size
limit. Truncated JSON is rejected and left unacknowledged. Do not concatenate repeated
reads or split FFE2 commands without a firmware-defined framing protocol.

Verify the 23-byte TIME:SYNC command and the longest ACK command fit negotiated write
payload sizes. The app prefers write-with-response when FFE2 supports it. FFE1 must emit
complete tokens (or newline-separated tokens); arbitrary fragmentation without framing
cannot be safely reconstructed. Check rapid MODE:APPLIED / SESSION:ENDED /
SESSION:STARTED / SESSION:SYNC ordering, both snapshot orders, DEFERRED then APPLIED,
readiness during an ongoing import, ACK loss, disconnect during a read/commit, critical
battery import, power reset, and restart/reimport after SQLite commit but before ACK.

EVENTLOG:START is a consent gate, not cryptographic phone identity. Another BLE client
can issue it. Do not claim stored records are restricted to a previously paired phone.
Device-side bonding and encrypted characteristic permissions need implementation and
Android/iOS hardware validation before such a claim is made.

## Validation in this workspace

`flutter analyze --no-pub`: no issues.
`flutter test --no-pub`: 169 passed, 2 skipped.
Coverage includes SQLite v1-to-v2 migration, durable commit ordering, duplicate/conflict
handling, truncated reads, ACK retries, connection invalidation, deferred clocks,
mode-specific session refresh, and a guest Analytics view backed by real SQLite.
Live Supabase and hardware tests remain outstanding as described above.
