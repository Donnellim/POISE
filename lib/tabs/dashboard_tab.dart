import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../activity_mode.dart';
import '../widgets/poise_app_bar.dart';
import '../bluetooth/poise_ble_service.dart';
import '../notifications/notification_center.dart';
import '../database/local_database.dart';
import '../database/models.dart';
import '../database/sync_service.dart';
import '../database/network_service.dart';
import '../auth/social_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({
    super.key,
    required this.activeMode,
    this.onBaselineSet,
    this.isBluetoothConnected,
    this.onBluetoothChanged,
    this.triggerRecalibration = false,
    this.onRecalibrationHandled,
  });

  final ActivityMode activeMode;
  final VoidCallback? onBaselineSet;
  final bool? isBluetoothConnected;
  final ValueChanged<bool>? onBluetoothChanged;
  final bool triggerRecalibration;
  final VoidCallback? onRecalibrationHandled;

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  // ── 1. Bluetooth State & Baseline Calibration ──
  bool _isBluetoothConnected = true;
  bool _isReconnecting = false;
  bool _isCalibrated = true;

  // ── 2. Cloud Sync State (Separate & Independent) ──
  bool _isCloudSynced = true;
  bool _isSyncing = false;

  // ── 3. Real-Time Pitch Angle (Degrees from POISE Sensor) ──
  double? _livePostureAngle;
  double _sessionBaselineAngle = 0.0;

  // ── 4. Slouch Correction Tracking ──
  DateTime? _activeSlouchStartTime;
  double _peakSlouchAngle = 0.0;

  // ── 5. Session Elapsed Timer & Controls ──
  bool _isSessionRunning = false;
  bool _isSessionPaused = false;
  int _sessionSeconds = 0;
  Timer? _sessionTimer;
  bool _calibrationDialogOpen = false;
  StreamSubscription<double>? _blePitchSub;
  StreamSubscription<int>? _bleDeviceSessionSub;
  StreamSubscription<PoiseDeviceSessionAction>? _bleDeviceSessionActionSub;
  StreamSubscription<int>? _bleBatterySub;
  int _batteryLevel = 100;
  DateTime? _lastAlertNotificationTime;
  String? _currentSessionId;

  Future<void> _syncActiveSessionWithDeviceAndDatabase() async {
    try {
      // 1. If BLE hardware already reported elapsed session duration
      final devSec = PoiseBleService.instance.deviceSessionSeconds;
      if (devSec > 0 && mounted) {
        setState(() {
          _sessionSeconds = devSec;
          _isSessionRunning = true;
          _isSessionPaused = false;
          _isCalibrated = true;
          _livePostureAngle = PoiseBleService.instance.currentPitchAngle;
        });
        await _ensureActiveSessionStarted();
        return;
      }

      // 2. Check if an active monitoring session exists in local database
      final active = await PoiseLocalDatabase.instance.getLatestActiveSession();
      if (active != null) {
        final elapsed = DateTime.now().difference(active.startedAt).inSeconds;
        if (mounted) {
          setState(() {
            _currentSessionId = active.id;
            _sessionBaselineAngle = active.baselineAngle;
            _sessionSeconds = math.max(_sessionSeconds, elapsed);
            _isSessionRunning = true;
            _isSessionPaused = false;
            _isCalibrated = true;
            _livePostureAngle = PoiseBleService.instance.currentPitchAngle;
          });
        }
        return;
      }

      // 3. When session is not currently running, sync Session Elapsed display with today's wear time
      // so the user sees their wear time reflecting 1:1 with Analytics
      final todaySec =
          await PoiseLocalDatabase.instance.getTodayTotalWearSeconds();
      if (todaySec > 0 && mounted && !_isSessionRunning) {
        setState(() {
          _sessionSeconds = todaySec;
        });
      }
    } catch (_) {}
  }

  Future<void> _ensureActiveSessionStarted({double? baselineAngle}) async {
    if (!_canMonitor) return;
    if (_currentSessionId != null) return;
    try {
      final user = SocialAuth.instance.user;
      final userId = user?.id ?? 'local_user';
      final modeId = ModeModel.idForActivityMode(widget.activeMode);
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('poise.deviceId') ?? 'POISE-DEVICE';
      final now = DateTime.now();

      _sessionBaselineAngle = baselineAngle ?? _sessionBaselineAngle;
      _currentSessionId = 'sess_${now.millisecondsSinceEpoch}';
      final startedAt = now.subtract(Duration(seconds: _sessionSeconds));
      await PoiseLocalDatabase.instance.insertSession(
        SessionModel(
          id: _currentSessionId!,
          deviceId: deviceId,
          userId: userId,
          modeId: modeId,
          startedAt: startedAt,
          updatedAt: now,
          baselineAngle: _sessionBaselineAngle,
          synced: false,
        ),
      );

      if (_isCloudSynced &&
          user != null &&
          NetworkService.instance.isConnected) {
        unawaited(SyncService.instance.syncToCloud());
      }
    } catch (_) {}
  }

  Future<void> _startNewSession({bool fromHardware = false}) async {
    if (!_isBluetoothConnected) return;

    // One calibration per session: tare zero baseline to current sensor angle
    final currentRaw = PoiseBleService.instance.rawPitchAngle;
    _sessionBaselineAngle = currentRaw;
    await PoiseBleService.instance.setZeroBaseline(baselinePitch: currentRaw);

    if (!fromHardware) {
      await PoiseBleService.instance.sendSessionCommand('SESSION:START');
    }

    _closeCurrentSession();

    setState(() {
      _isCalibrated = true;
      _isSessionRunning = true;
      _isSessionPaused = false;
      _sessionSeconds = 0;
      _livePostureAngle = null; // Await fresh telemetry from FFE1
      _activeSlouchStartTime = null;
      _peakSlouchAngle = 0.0;
    });

    await _ensureActiveSessionStarted(baselineAngle: currentRaw);
    _startTimer();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            fromHardware
                ? 'Device session started! Calibrated baseline set.'
                : 'New session started! Baseline calibrated at ${currentRaw >= 0 ? "+" : ""}${currentRaw.toStringAsFixed(1)}°',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _pauseSession({bool fromHardware = false}) {
    if (!_isSessionRunning || _isSessionPaused) return;
    _sessionTimer?.cancel();
    if (!fromHardware) {
      PoiseBleService.instance.sendSessionCommand('SESSION:PAUSE');
    }
    setState(() {
      _isSessionPaused = true;
      _livePostureAngle = null; // Stop presenting incoming values as active session readings
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session paused.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _resumeSession({bool fromHardware = false}) {
    if (!_isSessionRunning || !_isSessionPaused) return;
    if (!fromHardware) {
      PoiseBleService.instance.sendSessionCommand('SESSION:RESUME');
    }
    setState(() {
      _isSessionPaused = false;
    });
    _startTimer();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session resumed.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _endCurrentSession({bool fromHardware = false}) async {
    // If user was slouching when session ended, finalize the posture event
    if (_activeSlouchStartTime != null) {
      final now = DateTime.now();
      final correctionTime =
          now.difference(_activeSlouchStartTime!).inMilliseconds / 1000.0;
      final occurredAt = _activeSlouchStartTime!;
      final peakAngle = _peakSlouchAngle;
      _activeSlouchStartTime = null;
      _peakSlouchAngle = 0.0;

      if (_currentSessionId != null) {
        final eventId = ensureUuid('evt_${occurredAt.microsecondsSinceEpoch}');
        await PoiseLocalDatabase.instance.insertPostureEvent(
          PostureEventModel(
            id: eventId,
            sessionId: _currentSessionId!,
            occurredAt: occurredAt,
            tiltAngle: peakAngle,
            durationSec: correctionTime,
            feedbackTriggered: true,
            correctedAt: now,
            correctionTimeSec: correctionTime,
            synced: false,
          ),
        );
      }
    }

    if (!fromHardware) {
      await PoiseBleService.instance.sendSessionCommand('SESSION:END');
    }

    _closeCurrentSession();

    final todaySec =
        await PoiseLocalDatabase.instance.getTodayTotalWearSeconds();

    if (mounted) {
      setState(() {
        _isSessionRunning = false;
        _isSessionPaused = false;
        _livePostureAngle = null; // Clear live posture reading
        _sessionSeconds = todaySec > 0 ? todaySec : _sessionSeconds;
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(fromHardware
              ? 'Session ended on device. Posture data saved to analytics.'
              : 'Session ended. Posture data saved to analytics.'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _toggleSession() {
    if (!_canMonitor && !_isSessionRunning) return;
    if (_isSessionRunning) {
      _endCurrentSession();
    } else {
      _startNewSession();
    }
  }

  Future<void> _flushRealtimePostureData() async {
    try {
      final user = SocialAuth.instance.user;
      final userId = user?.id ?? 'local_user';
      final modeId = ModeModel.idForActivityMode(widget.activeMode);
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('poise.deviceId') ?? 'POISE-DEVICE';
      final now = DateTime.now();

      _currentSessionId ??= 'sess_${now.millisecondsSinceEpoch}';

      await PoiseLocalDatabase.instance.insertSession(
        SessionModel(
          id: _currentSessionId!,
          deviceId: deviceId,
          userId: userId,
          modeId: modeId,
          startedAt: now.subtract(Duration(seconds: _sessionSeconds)),
          updatedAt: now,
          baselineAngle: _sessionBaselineAngle,
          synced: false,
        ),
      );
    } catch (_) {}
  }

  bool get _shouldTrackDatabaseSession =>
      !PoiseBleService.instance.isTesting;

  void _closeCurrentSession() {
    if (_activeSlouchStartTime != null) {
      final now = DateTime.now();
      final correctionTime =
          now.difference(_activeSlouchStartTime!).inMilliseconds / 1000.0;
      final occurredAt = _activeSlouchStartTime!;
      final peakAngle = _peakSlouchAngle;
      _activeSlouchStartTime = null;
      _peakSlouchAngle = 0.0;

      if (_currentSessionId != null) {
        final eventId = ensureUuid('evt_${occurredAt.microsecondsSinceEpoch}');
        unawaited(PoiseLocalDatabase.instance.insertPostureEvent(
          PostureEventModel(
            id: eventId,
            sessionId: _currentSessionId!,
            occurredAt: occurredAt,
            tiltAngle: peakAngle,
            durationSec: correctionTime,
            feedbackTriggered: true,
            correctedAt: now,
            correctionTimeSec: correctionTime,
            synced: false,
          ),
        ));
      }
    }

    if (_currentSessionId != null) {
      final sId = _currentSessionId!;
      _currentSessionId = null;
      if (_shouldTrackDatabaseSession) {
        unawaited(PoiseLocalDatabase.instance.endSession(sId, DateTime.now()));
        if (_isCloudSynced &&
            SocialAuth.instance.user != null &&
            NetworkService.instance.isConnected) {
          unawaited(SyncService.instance.syncToCloud());
        }
      }
    }
  }

  bool get _canMonitor => _isBluetoothConnected && _isCalibrated;

  @override
  void initState() {
    super.initState();
    NetworkService.instance.isConnectedNotifier
        .addListener(_onNetworkStatusChanged);
    SyncService.instance.status.addListener(_onSyncStatusChanged);
    unawaited(SyncService.instance.restoreFromCloud());
    _sessionBaselineAngle = PoiseBleService.instance.zeroBaselineOffset;
    if (PoiseBleService.instance.isTesting) {
      _isSessionRunning = true;
      _livePostureAngle = 0.0;
    }
    if (widget.isBluetoothConnected != null) {
      _isBluetoothConnected = widget.isBluetoothConnected!;
      if (!_isBluetoothConnected) {
        _isSessionRunning = false;
        _livePostureAngle = null;
      }
    }
    _startTimer();
    _syncActiveSessionWithDeviceAndDatabase();

    _batteryLevel = PoiseBleService.instance.batteryLevel;
    _bleBatterySub = PoiseBleService.instance.batteryLevelStream.listen((bat) {
      if (mounted) {
        setState(() {
          _batteryLevel = bat;
        });
      }
    });

    _bleDeviceSessionSub =
        PoiseBleService.instance.deviceSessionSecondsStream.listen((sec) {
      if (mounted) {
        setState(() {
          _sessionSeconds = sec;
          _isSessionRunning = true;
          _isCalibrated = true;
        });
        if (_currentSessionId != null) {
          unawaited(PoiseLocalDatabase.instance.updateSessionProgress(
            _currentSessionId!,
            DateTime.now(),
          ));
        } else {
          _ensureActiveSessionStarted();
        }
      }
    });

    _bleDeviceSessionActionSub =
        PoiseBleService.instance.deviceSessionActionStream.listen((action) {
      if (!mounted) return;
      switch (action) {
        case PoiseDeviceSessionAction.started:
          if (!_isSessionRunning) {
            _startNewSession(fromHardware: true);
          }
          break;
        case PoiseDeviceSessionAction.paused:
          _pauseSession(fromHardware: true);
          break;
        case PoiseDeviceSessionAction.resumed:
          _resumeSession(fromHardware: true);
          break;
        case PoiseDeviceSessionAction.ended:
          if (_isSessionRunning) {
            _endCurrentSession(fromHardware: true);
          }
          break;
      }
    });

    _blePitchSub = PoiseBleService.instance.pitchAngleStream.listen((angle) {
      if (mounted && _canMonitor) {
        if (!_isSessionRunning || _isSessionPaused) {
          // When monitoring is inactive or paused, do NOT present incoming values as active session readings
          return;
        }
        setState(() {
          _livePostureAngle = angle;
          if (_isSessionRunning) {
            final isSlouched = angle.abs() > widget.activeMode.angle;
            final now = DateTime.now();

            if (isSlouched) {
              if (_activeSlouchStartTime == null) {
                // Posture deviation detected: start tracking duration and peak angle
                _activeSlouchStartTime = now;
                _peakSlouchAngle = angle;

                if (_lastAlertNotificationTime == null ||
                    now.difference(_lastAlertNotificationTime!) >
                        const Duration(seconds: 15)) {
                  _lastAlertNotificationTime = now;
                  NotificationScope.of(context)?.add(PoiseNoticeType.alert);
                }

                if (_currentSessionId == null) {
                  _currentSessionId = 'sess_${now.millisecondsSinceEpoch}';
                  _ensureActiveSessionStarted();
                }
              } else {
                // Slouch is continuing: track the peak slouch angle
                if (angle.abs() > _peakSlouchAngle.abs()) {
                  _peakSlouchAngle = angle;
                }
              }
            } else {
              // User corrected posture! 1 posture event = improper posture detected -> corrected.
              if (_activeSlouchStartTime != null) {
                final correctedAt = now;
                final correctionTime = correctedAt
                        .difference(_activeSlouchStartTime!)
                        .inMilliseconds /
                    1000.0;
                final occurredAt = _activeSlouchStartTime!;
                final peakAngle = _peakSlouchAngle;
                _activeSlouchStartTime = null;
                _peakSlouchAngle = 0.0;

                if (_currentSessionId == null) {
                  _currentSessionId = 'sess_${now.millisecondsSinceEpoch}';
                  _ensureActiveSessionStarted();
                }
                final sId = _currentSessionId!;
                final eventId =
                    ensureUuid('evt_${occurredAt.microsecondsSinceEpoch}');

                // Insert the single complete posture event
                unawaited(PoiseLocalDatabase.instance.insertPostureEvent(
                  PostureEventModel(
                    id: eventId,
                    sessionId: sId,
                    occurredAt: occurredAt,
                    tiltAngle: peakAngle,
                    durationSec: correctionTime,
                    feedbackTriggered: true,
                    correctedAt: correctedAt,
                    correctionTimeSec: correctionTime,
                    synced: false,
                  ),
                ));

                // Real-time cloud sync: immediately sync the completed event
                if (_isCloudSynced &&
                    SocialAuth.instance.user != null &&
                    NetworkService.instance.isConnected) {
                  unawaited(SyncService.instance.syncToCloud());
                }
              }
            }
          }
        });
      }
    });
  }

  @override
  void didUpdateWidget(DashboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isBluetoothConnected != null &&
        widget.isBluetoothConnected != _isBluetoothConnected) {
      if (widget.isBluetoothConnected == false) {
        setState(() {
          _isBluetoothConnected = false;
          _isSessionRunning = false;
          _isSessionPaused = false;
          _livePostureAngle = null;
        });
      } else {
        setState(() {
          _isBluetoothConnected = true;
          _isSessionRunning = _isCalibrated;
          _isSessionPaused = false;
          if (_isCalibrated) {
            _livePostureAngle = PoiseBleService.instance.currentPitchAngle;
          }
        });
        _syncActiveSessionWithDeviceAndDatabase();
      }
    }

    if (widget.triggerRecalibration && !oldWidget.triggerRecalibration) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onRecalibrationHandled?.call();
        if (mounted && _isBluetoothConnected) {
          _showRecalibrationDialog();
        }
      });
    }

    if (widget.activeMode != oldWidget.activeMode && _currentSessionId != null) {
      unawaited(PoiseLocalDatabase.instance.updateSessionMode(
        _currentSessionId!,
        ModeModel.idForActivityMode(widget.activeMode),
      ));
    }
  }

  void _startTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isSessionRunning && !_isSessionPaused && _canMonitor) {
        setState(() {
          _sessionSeconds++;
        });
        if (_shouldTrackDatabaseSession) {
          if (_sessionSeconds == 1 || _currentSessionId == null) {
            _ensureActiveSessionStarted();
          } else {
            if (_sessionSeconds % 5 == 0 && _currentSessionId != null) {
              unawaited(PoiseLocalDatabase.instance.updateSessionProgress(
                _currentSessionId!,
                DateTime.now(),
              ));
            }
          }
        }
      }
    });
  }

  void _onNetworkStatusChanged() {
    if (mounted) setState(() {});
  }

  void _onSyncStatusChanged() {
    if (mounted) {
      setState(() {
        _isSyncing = SyncService.instance.isSyncing;
        if (SyncService.instance.status.value == SyncStatus.success) {
          _isCloudSynced = true;
        }
      });
    }
  }

  @override
  void dispose() {
    NetworkService.instance.isConnectedNotifier
        .removeListener(_onNetworkStatusChanged);
    SyncService.instance.status.removeListener(_onSyncStatusChanged);
    _blePitchSub?.cancel();
    _bleDeviceSessionSub?.cancel();
    _bleDeviceSessionActionSub?.cancel();
    _bleBatterySub?.cancel();
    _sessionTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    if (!_canMonitor) return '00:00:00';
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // SEPARATE INTERACTION 1: BLUETOOTH CONNECTION
  // ─────────────────────────────────────────────────────────────────────────────

  void _handleBluetoothTap() {
    if (_isReconnecting) return;
    if (_isBluetoothConnected) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFDCEEF6),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C853).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.bluetooth_connected,
                        color: Color(0xFF00C853), size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'P.O.I.S.E. Device Connected',
                        style: TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'POISE Device • Battery: $_batteryLevel%',
                        style: const TextStyle(color: Colors.black54, fontSize: 12.5),
                      ),
                    ],
                  )),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _closeCurrentSession();
                    PoiseBleService.instance.disconnect();
                    setState(() {
                      _isBluetoothConnected = false;
                      _isSessionRunning = false;
                    });
                    widget.onBluetoothChanged?.call(false);
                  },
                  icon: const Icon(Icons.bluetooth_disabled_rounded),
                  label: const Text('Disconnect Device',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF5350),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      );
    } else {
      _reconnectBluetooth();
    }
  }

  Future<void> _reconnectBluetooth() async {
    setState(() => _isReconnecting = true);
    final ble = PoiseBleService.instance;
    try {
      if (!await ble.isBluetoothAdapterOn()) {
        if (!await ble.requestEnableBluetooth()) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Turn on Bluetooth in your phone settings, then tap Bluetooth here to reconnect.'),
            ));
          }
          return;
        }
      }
      bool connected = await ble.restoreConnection();
      if (!connected) {
        connected = await ble.checkAndConnectSystemDevice();
      }
      if (!mounted) return;
      if (connected) {
        setState(() {
          _isBluetoothConnected = true;
          _isSessionRunning = _isCalibrated;
        });
        widget.onBluetoothChanged?.call(true);
      } else {
        _showReconnectFailure();
      }
    } catch (_) {
      if (mounted) _showReconnectFailure();
    } finally {
      if (mounted) setState(() => _isReconnecting = false);
    }
  }

  void _showReconnectFailure() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text(
          'Could not reconnect to your P.O.I.S.E. device. Make sure it is powered on and nearby, then tap Bluetooth to retry.'),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // SEPARATE INTERACTION 2: CLOUD SYNC
  // ─────────────────────────────────────────────────────────────────────────────

  void _handleCloudSyncTap() {
    final user = SocialAuth.instance.user;
    final isGuest = user == null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFDCEEF6),
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (!NetworkService.instance.isConnected
                              ? Colors.orange
                              : (isGuest
                                  ? Colors.grey
                                  : (_isCloudSynced
                                      ? const Color(0xFF0288D1)
                                      : Colors.orange)))
                          .withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      !NetworkService.instance.isConnected
                          ? Icons.cloud_off_rounded
                          : (isGuest
                              ? Icons.person_off_rounded
                              : (_isCloudSynced
                                  ? Icons.cloud_done_rounded
                                  : Icons.sync_rounded)),
                      color: !NetworkService.instance.isConnected
                          ? Colors.orange[800]
                          : (isGuest
                              ? Colors.grey[700]
                              : (_isCloudSynced
                                  ? const Color(0xFF0288D1)
                                  : Colors.orange[800])),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        !NetworkService.instance.isConnected
                            ? 'Cloud Sync: Offline'
                            : (isGuest
                                ? 'Cloud Sync: Guest Mode'
                                : (_isCloudSynced
                                    ? 'Cloud Sync: Active'
                                    : 'Cloud Sync: Pending')),
                        style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      Text(
                        !NetworkService.instance.isConnected
                            ? 'No internet connection • Mobile data and Wi-Fi are disconnected. Telemetry is saved locally and will auto-sync when reconnected.'
                            : (isGuest
                                ? 'Signed in as Guest. Cloud sync is only available for accounts. Go to Profile tab to sign in.'
                                : (_isCloudSynced
                                    ? 'Connected as ${user.email ?? 'User'} • Auto-backup enabled'
                                    : 'Online • Unsynced records ready to backup to cloud')),
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 12.5),
                      ),
                    ],
                  )),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    if (!NetworkService.instance.isConnected) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFFE53935),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          content: const Row(
                            children: [
                              Icon(Icons.cloud_off_rounded,
                                  color: Colors.white),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Cannot sync while offline. Please connect to Wi-Fi or mobile data.',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          duration: const Duration(seconds: 4),
                        ),
                      );
                      return;
                    }
                    setModalState(() => _isSyncing = true);
                    setState(() => _isSyncing = true);
                    await _flushRealtimePostureData();
                    final success = await SyncService.instance.syncToCloud();
                    await Future.delayed(const Duration(milliseconds: 300));
                    if (!mounted) return;
                    setState(() {
                      _isSyncing = false;
                      _isCloudSynced = success;
                    });
                    if (context.mounted) {
                      Navigator.pop(context);
                      final errorMsg = SyncService.instance.lastError.value;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: success
                              ? const Color(0xFF0288D1)
                              : const Color(0xFFE53935),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          content: Row(
                            children: [
                              Icon(
                                  success
                                      ? Icons.check_circle_outline
                                      : Icons.cloud_off_rounded,
                                  color: Colors.white),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  success
                                      ? 'All posture session logs synced to cloud!'
                                      : (errorMsg ??
                                          'Saved locally. Will sync when cloud is reachable.'),
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                  },
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded),
                  label: Text(
                    _isSyncing ? 'Syncing...' : 'Sync Posture Data Now',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0288D1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _generateDemoTelemetryAndSync();
                  },
                  icon: const Icon(Icons.science_outlined, size: 20),
                  label: const Text('Simulate Test Session & Sync'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0288D1),
                    side: const BorderSide(color: Color(0xFF0288D1)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    PoiseBleService.instance.simulatePitchAngle(18.5);
                  },
                  icon: const Icon(Icons.airline_seat_recline_extra_rounded, size: 20),
                  label: const Text('Simulate Realtime Slouch (+18.5°)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF5350),
                    side: const BorderSide(color: Color(0xFFEF5350)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    PoiseBleService.instance.simulatePitchAngle(0.0);
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text('Reset Pitch Angle (0.0°)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2E7D32),
                    side: const BorderSide(color: Color(0xFF2E7D32)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    if (PoiseBleService.instance.isMockStreaming) {
                      PoiseBleService.instance.stopMockTelemetryStream();
                    } else {
                      PoiseBleService.instance.startMockTelemetryStream();
                    }
                  },
                  icon: Icon(
                    PoiseBleService.instance.isMockStreaming
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    size: 20,
                  ),
                  label: Text(PoiseBleService.instance.isMockStreaming
                      ? 'Stop Live Sensor Drift'
                      : 'Start Live Sensor Drift (0° ↔ 18°)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00838F),
                    side: const BorderSide(color: Color(0xFF00838F)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    setState(() {
                      _isCloudSynced = !_isCloudSynced;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: const BorderSide(color: Colors.black26),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(_isCloudSynced
                      ? 'Pause Cloud Sync (Offline)'
                      : 'Enable Cloud Sync'),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    ),
  ),
);
}

  Future<void> _generateDemoTelemetryAndSync() async {
    try {
      final user = SocialAuth.instance.user;
      final isGuest = user == null;
      final userId = user?.id ?? 'local_user';
      final now = DateTime.now();

      // 1. Ensure test device exists
      const testDeviceId = 'POISE-DEVICE';
      await PoiseLocalDatabase.instance.upsertDevice(
        DeviceModel(
          id: testDeviceId,
          userId: userId,
          deviceName: 'POISE Device',
          pairedAt: now.subtract(const Duration(hours: 3)),
          lastSeenAt: now,
          updatedAt: now,
        ),
      );

      // 2. Insert two realistic sessions with clean baseline angles
      final session1Id =
          ensureUuid('sess_demo_focus_${now.millisecondsSinceEpoch}');
      await PoiseLocalDatabase.instance.insertSession(
        SessionModel(
          id: session1Id,
          deviceId: testDeviceId,
          userId: userId,
          modeId: ModeModel.idForActivityMode(ActivityMode.focus),
          startedAt: now.subtract(const Duration(minutes: 90)),
          endedAt: now.subtract(const Duration(minutes: 45)),
          updatedAt: now.subtract(const Duration(minutes: 45)),
          baselineAngle: 12.0,
          synced: false,
        ),
      );

      final session2Id =
          ensureUuid('sess_demo_normal_${now.millisecondsSinceEpoch}');
      await PoiseLocalDatabase.instance.insertSession(
        SessionModel(
          id: session2Id,
          deviceId: testDeviceId,
          userId: userId,
          modeId: ModeModel.idForActivityMode(widget.activeMode),
          startedAt: now.subtract(const Duration(minutes: 40)),
          endedAt: now.subtract(const Duration(minutes: 5)),
          updatedAt: now,
          baselineAngle: 15.0,
          synced: false,
        ),
      );

      // 3. Insert realistic posture events with complete correction metrics
      final events = <PostureEventModel>[
        // Events in Session 1 (Focus Mode: 10° threshold)
        PostureEventModel(
          id: ensureUuid('evt_demo_1_${now.millisecondsSinceEpoch}'),
          sessionId: session1Id,
          occurredAt: now.subtract(const Duration(minutes: 80)),
          tiltAngle: 17.5,
          durationSec: 2.1,
          feedbackTriggered: true,
          correctedAt: now
              .subtract(const Duration(minutes: 80))
              .add(const Duration(milliseconds: 2100)),
          correctionTimeSec: 2.1,
          synced: false,
        ),
        PostureEventModel(
          id: ensureUuid('evt_demo_2_${now.millisecondsSinceEpoch}'),
          sessionId: session1Id,
          occurredAt: now.subtract(const Duration(minutes: 65)),
          tiltAngle: 21.0,
          durationSec: 3.4,
          feedbackTriggered: true,
          correctedAt: now
              .subtract(const Duration(minutes: 65))
              .add(const Duration(milliseconds: 3400)),
          correctionTimeSec: 3.4,
          synced: false,
        ),
        PostureEventModel(
          id: ensureUuid('evt_demo_3_${now.millisecondsSinceEpoch}'),
          sessionId: session1Id,
          occurredAt: now.subtract(const Duration(minutes: 50)),
          tiltAngle: 15.2,
          durationSec: 1.8,
          feedbackTriggered: true,
          correctedAt: now
              .subtract(const Duration(minutes: 50))
              .add(const Duration(milliseconds: 1800)),
          correctionTimeSec: 1.8,
          synced: false,
        ),

        // Events in Session 2 (Current Mode: Normal / Leisure / Commuting)
        PostureEventModel(
          id: ensureUuid('evt_demo_4_${now.millisecondsSinceEpoch}'),
          sessionId: session2Id,
          occurredAt: now.subtract(const Duration(minutes: 32)),
          tiltAngle: 22.4,
          durationSec: 3.1,
          feedbackTriggered: true,
          correctedAt: now
              .subtract(const Duration(minutes: 32))
              .add(const Duration(milliseconds: 3100)),
          correctionTimeSec: 3.1,
          synced: false,
        ),
        PostureEventModel(
          id: ensureUuid('evt_demo_5_${now.millisecondsSinceEpoch}'),
          sessionId: session2Id,
          occurredAt: now.subtract(const Duration(minutes: 20)),
          tiltAngle: 26.8,
          durationSec: 4.5,
          feedbackTriggered: true,
          correctedAt: now
              .subtract(const Duration(minutes: 20))
              .add(const Duration(milliseconds: 4500)),
          correctionTimeSec: 4.5,
          synced: false,
        ),
        PostureEventModel(
          id: ensureUuid('evt_demo_6_${now.millisecondsSinceEpoch}'),
          sessionId: session2Id,
          occurredAt: now.subtract(const Duration(minutes: 10)),
          tiltAngle: 19.0,
          durationSec: 2.2,
          feedbackTriggered: true,
          correctedAt: now
              .subtract(const Duration(minutes: 10))
              .add(const Duration(milliseconds: 2200)),
          correctionTimeSec: 2.2,
          synced: false,
        ),
      ];

      await PoiseLocalDatabase.instance.insertPostureEventsBatch(events);
      PoiseLocalDatabase.instance.notifyDatabaseChanged();

      if (isGuest) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF0288D1),
            behavior: SnackBarBehavior.floating,
            content: Text(
              'Simulated 2 sessions & 6 posture events in local database! To sync to Supabase Cloud, sign in in Profile tab.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      // 4. Trigger cloud sync for authenticated account
      setState(() => _isSyncing = true);
      final success = await SyncService.instance.syncToCloud();
      if (!mounted) return;
      setState(() {
        _isSyncing = false;
        _isCloudSynced = success;
      });

      final errorMsg = SyncService.instance.lastError.value;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor:
              success ? const Color(0xFF0288D1) : const Color(0xFFE53935),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Text(
            success
                ? 'Simulated 2 test sessions & 6 posture events synced to Supabase Cloud! Verified all columns.'
                : (errorMsg ??
                    'Demo data generated locally. Connect internet to sync.'),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate test data: $e')),
      );
    }
  }

  // ── Recalibration Flow: Zero Baseline Dialog ──
  Future<void> _showRecalibrationDialog() async {
    if (!_isBluetoothConnected || _calibrationDialogOpen) return;
    _calibrationDialogOpen = true;
    setState(() {
      _isCalibrated = false;
      _isSessionRunning = false;
    });
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFFDCEEF6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Color(0xFF4285F4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.sync_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Set Your Neutral Posture',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Sit with your back straight, shoulders relaxed, and head facing forward.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black.withValues(alpha: 0.8),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: const BorderSide(color: Colors.black, width: 1),
                    ),
                  ),
                  child: const Text(
                    'Set Zero Baseline',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel',
                    style: TextStyle(color: Colors.black87)),
              ),
            ],
          ),
        ),
      ),
    );
    _calibrationDialogOpen = false;
    if (!mounted || !_isBluetoothConnected || confirmed != true) return;
    _showCalibratedOverlay();
  }

  void _showCalibratedOverlay() {
    if (!_isBluetoothConnected) return;
    PoiseBleService.instance.setZeroBaseline();
    widget.onBaselineSet?.call();
    setState(() {
      _isCalibrated = true;
      _livePostureAngle = 0.0;
      _sessionSeconds = 0;
      _isSessionRunning = true;
    });

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFF4DB6AC),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: const BoxDecoration(
                  color: Color(0xFFB2DFDB),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Color(0xFF00796B),
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Baseline Established!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your neutral posture has been set.\nYou can now start monitoring your posture.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: Colors.black, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4285F4),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                      side: const BorderSide(color: Colors.black, width: 1),
                    ),
                  ),
                  child: const Text('Done',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 76),
      child: Column(
        children: [
          const PoiseHeader(),
          const SizedBox(height: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox.expand(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: _buildDashboardContent(),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Status Pill Bar (Separately Interactable: Bluetooth & Cloud Sync) ──
        Container(
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFAFE0EE), // Light-cyan pill background
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: Colors.black.withValues(alpha: 0.1), width: 1),
          ),
          child: Row(
            children: [
              // ── 1. Bluetooth Status (Separate Tap Handler) ──
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _handleBluetoothTap,
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(12)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isBluetoothConnected
                              ? Icons.bluetooth
                              : Icons.bluetooth_disabled_rounded,
                          color: _isBluetoothConnected
                              ? const Color(0xFF00C853)
                              : Colors.red,
                          size: 19,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                            child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _isBluetoothConnected
                                ? 'Device Connected'
                                : (_isReconnecting
                                    ? 'Reconnecting...'
                                    : 'Not Connected'),
                            style: TextStyle(
                              color: _isBluetoothConnected
                                  ? const Color(0xFF00C853)
                                  : Colors.red,
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )),
                      ],
                    ),
                  ),
                ),
              ),

              // Vertical Divider Line
              Container(width: 1, height: 24, color: Colors.black26),

              // ── 2. Cloud Sync Status (Separate Tap Handler) ──
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _handleCloudSyncTap,
                    borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(12)),
                    child: Builder(builder: (context) {
                      final isOnline = NetworkService.instance.isConnected;
                      final isGuest = SocialAuth.instance.user == null;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_isSyncing)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black87),
                            )
                          else if (!isOnline)
                            const Icon(
                              Icons.cloud_off_rounded,
                              color: Colors.black45,
                              size: 19,
                            )
                          else if (isGuest)
                            const Icon(
                              Icons.cloud_off_rounded,
                              color: Colors.black54,
                              size: 19,
                            )
                          else
                            Icon(
                              _isCloudSynced
                                  ? Icons.cloud_done_rounded
                                  : Icons.sync_rounded,
                              color: _isCloudSynced
                                  ? Colors.black87
                                  : Colors.black54,
                              size: 19,
                            ),
                          const SizedBox(width: 8),
                          Text(
                            _isSyncing
                                ? 'Syncing...'
                                : (!isOnline
                                    ? 'Offline'
                                    : (isGuest
                                        ? 'Guest Mode'
                                        : (_isCloudSynced
                                            ? 'Cloud Sync'
                                            : 'Not Synced'))),
                            style: TextStyle(
                              color: (!isOnline || isGuest || !_isCloudSynced)
                                  ? Colors.black54
                                  : Colors.black87,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // ── Speedometer Gauge & Live Spine Model (Full Width, Compact Gaps) ──
        Builder(builder: (context) {
          final isLiveActive =
              _isSessionRunning && !_isSessionPaused && _canMonitor;
          final hasReading = isLiveActive && _livePostureAngle != null;
          final displayAngle = hasReading
              ? (_livePostureAngle! == _livePostureAngle!.roundToDouble()
                  ? '${_livePostureAngle!.toInt()}°'
                  : '${_livePostureAngle!.toStringAsFixed(1)}°')
              : '--°';

          return AspectRatio(
            aspectRatio: 318 / 340,
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: 318,
                height: 340,
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    CustomPaint(
                      key: const ValueKey('pitch-gauge'),
                      size: const Size(318, 185),
                      painter: _SpeedometerGaugePainter(
                        angle: hasReading ? _livePostureAngle! : 0.0,
                        isConnected: hasReading,
                      ),
                    ),

                    // 2. Center Reading Overlay (Cleanly positioned inside the arch without overlapping dial or needle)
                    Positioned(
                      top: 60,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayAngle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              shadows: [
                                Shadow(
                                    color: Colors.black38,
                                    offset: Offset(0, 2),
                                    blurRadius: 4),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'POSTURE DEVIATION',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 1),
                          const Text(
                            'PITCH ANGLE',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 6.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 3. Real-Time Dynamic 3D Holographic Spine & Posture Model
                    Positioned(
                      bottom: 0,
                      child: RealTimeSpineTracker(
                        pitchAngle: hasReading ? _livePostureAngle! : 0.0,
                        isConnected: hasReading,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 10),

        // ── Current Mode Card (Read-only Controls Summary) ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF55BCE0), // Soft teal-blue card
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CURRENT MODE',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Active Mode Sub-card (Read-only)
                    Expanded(
                      child: Semantics(
                        key: const ValueKey('active-mode-summary'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFA5DCF2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF67D1E0),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(widget.activeMode.icon,
                                    color: Colors.white, size: 20),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'ACTIVE MODE',
                                      style: TextStyle(
                                          color: Colors.black54,
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _canMonitor
                                          ? widget.activeMode.label
                                          : '---',
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Threshold Sub-card (Read-only)
                    Expanded(
                      child: Semantics(
                        key: const ValueKey('threshold-summary'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFA5DCF2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'TIME-UNDER-TENSION\nTHRESHOLD',
                                style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    height: 1.1),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _canMonitor
                                    ? widget.activeMode.threshold
                                    : '--°/--s',
                                style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _canMonitor
                                    ? 'Limit: ${widget.activeMode.angleRestrictionDisplay} • Forgiveness: ${widget.activeMode.forgivenessTimeDisplay}'
                                    : 'Limit: --° • Forgiveness: --s',
                                style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 7.5,
                                    fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ── Session Elapsed Card ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF55BCE0),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _isSessionRunning
                            ? (_isSessionPaused ? 'Session Paused' : 'Session Running')
                            : 'Session Inactive',
                        style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatDuration(_sessionSeconds),
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (_isSessionRunning) ...[
                GestureDetector(
                  key: const ValueKey('session-pause-toggle'),
                  onTap: _isBluetoothConnected
                      ? (_isSessionPaused ? _resumeSession : _pauseSession)
                      : null,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 5),
                    decoration: BoxDecoration(
                      color: _isSessionPaused
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFF57C00),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isSessionPaused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _isSessionPaused ? 'Resume' : 'Pause',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              GestureDetector(
                key: const ValueKey('session-toggle'),
                onTap: _isBluetoothConnected ? _toggleSession : null,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isSessionRunning
                        ? const Color(0xFFD32F2F)
                        : const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isSessionRunning
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _isSessionRunning ? 'End Session' : 'Start Session',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Speedometer Gauge Painter (No Gradient Wrap Bug)
// ─────────────────────────────────────────────────────────────────────────────

class _SpeedometerGaugePainter extends CustomPainter {
  final double angle;
  final bool isConnected;

  _SpeedometerGaugePainter({required this.angle, required this.isConnected});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, 158);
    final radius = size.width * 0.38;

    // Symmetrical Arc: Starts at 160° and sweeps 220° (Ends at 380° / 20°)
    const startAngle = 170.0 * math.pi / 180.0;
    const sweepAngle = 200.0 * math.pi / 180.0;

    final rect = Rect.fromCircle(center: center, radius: radius);

    // 1. Background Arc Track
    final bgPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, startAngle, sweepAngle, false, bgPaint);

    // 2. Color Gradient Arc (Green -> Yellow -> Red)
    // Canvas rotation guarantees zero wrap-around at bottom right!
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(startAngle);

    final sweepGradient = SweepGradient(
      startAngle: 0.0,
      endAngle: sweepAngle,
      colors: const [
        Color(0xFF00E676), // Bright Green (-60°)
        Color(0xFF76FF03), // Light green (-30°)
        Color(0xFFFFEA00), // Yellow (0°)
        Color(0xFFFF9100), // Orange (30°)
        Color(0xFFFF1744), // Red (60°)
      ],
      stops: const [0.0, 0.25, 0.50, 0.75, 1.0],
    );

    final arcPaint = Paint()
      ..shader = sweepGradient
          .createShader(Rect.fromCircle(center: Offset.zero, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(Rect.fromCircle(center: Offset.zero, radius: radius), 0,
        sweepAngle, false, arcPaint);
    canvas.restore();

    final gridPaint = Paint()
      ..color = const Color(0xFF126A84)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65;
    for (final offset in [-9.0, 8.0, 16.0, 24.0]) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius + offset),
          startAngle, sweepAngle, false, gridPaint);
    }

    // 3. Ticks & Degree Labels
    final tickPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 0.65;

    final List<int> majorTicks = [-60, -30, 0, 30, 60];

    for (int deg = -60; deg <= 60; deg += 6) {
      final double t = (deg + 60.0) / 120.0;
      final double rad = startAngle + t * sweepAngle;
      final bool isMajor = majorTicks.contains(deg);

      final double innerR = radius - (isMajor ? 12 : 6);
      final double outerR = radius + 24;

      final p1 = Offset(center.dx + innerR * math.cos(rad),
          center.dy + innerR * math.sin(rad));
      final p2 = Offset(center.dx + outerR * math.cos(rad),
          center.dy + outerR * math.sin(rad));

      canvas.drawLine(p1, p2, tickPaint);

      if (isMajor) {
        Color labelColor = Colors.black87;
        if (deg == -60) {
          labelColor = const Color(0xFF00E676);
        } else if (deg == -30) {
          labelColor = const Color(0xFF76FF03);
        } else if (deg == 0) {
          labelColor = const Color(0xFFFFD600);
        } else if (deg == 30) {
          labelColor = const Color(0xFFFF9100);
        } else if (deg == 60) {
          labelColor = const Color(0xFFFF1744);
        }

        final textSpan = TextSpan(
          text: '$deg°',
          style: TextStyle(
            color: labelColor,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();

        final double labelR = radius + 31;
        final labelOffset = Offset(
          center.dx + labelR * math.cos(rad) - textPainter.width / 2,
          center.dy + labelR * math.sin(rad) - textPainter.height / 2,
        );
        textPainter.paint(canvas, labelOffset);
      }
    }

    // 4. White Needle Indicator Line (Points to 0° when disconnected, or live angle when connected)
    final double needleDeg = isConnected ? angle.clamp(-60.0, 60.0) : 0.0;
    final double needleT = (needleDeg + 60.0) / 120.0;
    final double needleRad = startAngle + needleT * sweepAngle;

    final shadowPaint = Paint()
      ..color = Colors.black38
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;

    final needlePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final pStart = Offset(
      center.dx + (radius - 16) * math.cos(needleRad),
      center.dy + (radius - 16) * math.sin(needleRad),
    );
    final pEnd = Offset(
      center.dx + (radius + 8) * math.cos(needleRad),
      center.dy + (radius + 8) * math.sin(needleRad),
    );

    canvas.drawLine(
        pStart + const Offset(1, 2), pEnd + const Offset(1, 2), shadowPaint);
    canvas.drawLine(pStart, pEnd, needlePaint);

    canvas.drawCircle(pEnd, 4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _SpeedometerGaugePainter oldDelegate) {
    return oldDelegate.angle != angle || oldDelegate.isConnected != isConnected;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Real-Time Articulated 3D Holographic Spine Model Tracker
// ─────────────────────────────────────────────────────────────────────────────

class RealTimeSpineTracker extends StatelessWidget {
  final double pitchAngle;
  final bool isConnected;

  const RealTimeSpineTracker({
    super.key,
    required this.pitchAngle,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    final double targetAngle = isConnected ? pitchAngle : 0.0;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: targetAngle),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      builder: (context, animatedAngle, child) {
        // Biomechanical tilt angle in radians (scaled naturally for torso inclination)
        final double angleRad = (animatedAngle * math.pi / 180.0) * 0.72;

        Color auraColor;
        if (!isConnected) {
          auraColor = Colors.transparent;
        } else if (animatedAngle.abs() <= 10.0) {
          auraColor = const Color(0xFF00E5FF).withValues(alpha: 0.28);
        } else if (animatedAngle.abs() <= 15.0) {
          auraColor = const Color(0xFFFFD600).withValues(alpha: 0.30);
        } else {
          auraColor = const Color(0xFFFF3D00).withValues(alpha: 0.38);
        }

        return SizedBox(
          height: 182,
          width: 140,
          child: Stack(
            alignment: Alignment.bottomCenter,
            clipBehavior: Clip.none,
            children: [
              // Dynamic posture aura glow behind model
              if (isConnected)
                Positioned(
                  bottom: 20,
                  child: Container(
                    width: 100,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: auraColor,
                          blurRadius: 36,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),

              // The authentic 3D holographic spine model from spine_model.png,
              // dynamically articulated to follow the POISE pitch angle in real time.
              Transform(
                alignment: const Alignment(0.0, 0.95),
                transform: Matrix4.identity()
                  ..rotateZ(angleRad)
                  ..multiply(
                    Matrix4.translationValues(
                      math.sin(angleRad) * 6.0,
                      (1.0 - math.cos(angleRad)) * -4.0,
                      0.0,
                    ),
                  ),
                child: SizedBox(
                  height: 182,
                  width: 110,
                  child: Image.asset(
                    'assets/images/spine_model.png',
                    height: 182,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
