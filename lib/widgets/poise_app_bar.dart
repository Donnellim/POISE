import 'package:flutter/material.dart';
import '../notifications/notification_center.dart';

/// Shared device header for every main P.O.I.S.E. tab.
class PoiseHeader extends StatelessWidget {
  const PoiseHeader({super.key, this.batteryPercent = 100});

  final int batteryPercent;
  static const ink = Color(0xFF073344);
  static const batteryGreen = Color(0xFF00D900);

  @override
  Widget build(BuildContext context) {
    final level = batteryPercent.clamp(0, 100);
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Notifications',
                padding: EdgeInsets.zero,
                onPressed: () => showNotifications(context,
                    NotificationScope.of(context) ?? NotificationCenter()),
                icon: const Icon(Icons.notifications_rounded,
                    color: ink, size: 25),
              ),
            ),
          ),
          const Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('P.O.I.S.E.',
                    style: TextStyle(
                      color: ink,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    )),
              ),
            ),
          ),
          Semantics(
            label: 'POISE device battery: $level percent',
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
                        border: Border.all(color: batteryGreen, width: 2),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: level / 100,
                          heightFactor: 1,
                          child: Container(color: batteryGreen),
                        ),
                      ),
                    ),
                    Container(
                      width: 2,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: batteryGreen,
                        borderRadius:
                            BorderRadius.horizontal(right: Radius.circular(1)),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('$level%',
                                style: const TextStyle(
                                    color: ink, fontSize: 10)))),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
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
