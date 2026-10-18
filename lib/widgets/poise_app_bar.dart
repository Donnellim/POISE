import 'package:flutter/material.dart';
import '../bluetooth/poise_ble_service.dart';

/// Shared device header for every main P.O.I.S.E. tab.
class PoiseHeader extends StatelessWidget {
  const PoiseHeader({super.key, this.batteryPercent});

  final int? batteryPercent;
  static const ink = Color(0xFF073344);
  static const batteryGreen = Color(0xFF00D900);
  static const batteryAmber = Color(0xFFFFA000);
  static const batteryRed = Color(0xFFD32F2F);

  Color _getBatteryColor(int level) {
    if (level <= 20) return batteryRed;
    if (level <= 40) return batteryAmber;
    return batteryGreen;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: PoiseBleService.instance.isConnectedStream,
      initialData: PoiseBleService.instance.isConnected,
      builder: (context, connSnap) {
        final isConnected = connSnap.data ?? false;

        return StreamBuilder<int>(
          stream: PoiseBleService.instance.batteryLevelStream,
          initialData: PoiseBleService.instance.batteryLevel,
          builder: (context, batSnap) {
            final int rawLevel = batteryPercent ?? batSnap.data ?? 100;
            final int level = rawLevel.clamp(0, 100);
            final bool showActiveBattery = isConnected || batteryPercent != null;
            final Color color =
                showActiveBattery ? _getBatteryColor(level) : Colors.black38;

            return SizedBox(
              height: 28,
              child: Row(
                children: [
                  // Symmetrical empty space on the left ensuring 'P.O.I.S.E.' remains centered
                  // Notification bell is removed as notifications are dispatched to the phone's system panel
                  const SizedBox(width: 76),
                  const Expanded(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'P.O.I.S.E.',
                          style: TextStyle(
                            color: ink,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    label: showActiveBattery
                        ? 'POISE device battery: $level percent'
                        : 'POISE device disconnected',
                    child: ExcludeSemantics(
                      child: SizedBox(
                        width: 76,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              width: 25,
                              height: 14,
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                border: Border.all(color: color, width: 2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: FractionallySizedBox(
                                  widthFactor:
                                      showActiveBattery ? (level / 100) : 0,
                                  heightFactor: 1,
                                  child: Container(color: color),
                                ),
                              ),
                            ),
                            Container(
                              width: 2,
                              height: 6,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: const BorderRadius.horizontal(
                                    right: Radius.circular(1)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  showActiveBattery ? '$level%' : '--%',
                                  style: TextStyle(color: color, fontSize: 10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class PoiseAppBar extends StatelessWidget implements PreferredSizeWidget {
  const PoiseAppBar({super.key});

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF20A6D7),
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: const SafeArea(bottom: false, child: PoiseHeader()),
      );

  @override
  Size get preferredSize => const Size.fromHeight(56);
}
