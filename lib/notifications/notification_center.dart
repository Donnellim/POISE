import 'package:flutter/material.dart';

enum PoiseNoticeType {
  disconnected(
      'Device Disconnected',
      'Please check your P.O.I.S.E. connection.',
      Icons.bluetooth_disabled,
      Color(0xFFADE4F5)),
  lowBattery('Low Battery', 'Please charge your P.O.I.S.E. device.',
      Icons.battery_0_bar, Colors.red),
  reminder('Posture Reminder', 'Please adjust your posture.', Icons.accessible,
      Color(0xFFADE4F5)),
  alert('Posture Alert', 'Your posture needs adjustment.',
      Icons.warning_rounded, Colors.red),
  goodPosture(
      'Good Posture', 'Keep it up!', Icons.check_circle, Color(0xFF00D900)),
  connected('Device Connected', 'P.O.I.S.E. is ready to monitor your posture.',
      Icons.bluetooth, Color(0xFF388AF6)),
  charged('Fully Charged', 'Your P.O.I.S.E. device is ready to use.',
      Icons.battery_full, Color(0xFF00D900)),
  charging('Charging', 'P.O.I.S.E. is currently charging.',
      Icons.battery_charging_full, Color(0xFFE0EEF4));

  const PoiseNoticeType(this.title, this.message, this.icon, this.color);
  final String title;
  final String message;
  final IconData icon;
  final Color color;
}

class PoiseNotice {
  PoiseNotice(this.type, this.time, {this.read = false});
  final PoiseNoticeType type;
  final DateTime time;
  bool read;
}

class NotificationCenter extends ChangeNotifier {
  NotificationCenter({List<PoiseNotice>? initial}) : _items = [...?initial];

  // Preview data for the existing simulated device; replace with device events.
  factory NotificationCenter.preview() {
    final today = DateUtils.dateOnly(DateTime.now());
    return NotificationCenter(initial: [
      for (var i = 0; i < PoiseNoticeType.values.length; i++)
        PoiseNotice(PoiseNoticeType.values[i],
            today.add(Duration(minutes: 660 - i * 30))),
    ]);
  }

  final List<PoiseNotice> _items;
  List<PoiseNotice> get items => List.unmodifiable(_items);
  bool get hasUnread => _items.any((item) => !item.read);

  void add(PoiseNoticeType type) {
    _items.insert(0, PoiseNotice(type, DateTime.now()));
    notifyListeners();
  }

  void markAllRead() {
    for (final item in _items) {
      item.read = true;
    }
    notifyListeners();
  }

  void markRead(PoiseNotice item) {
    item.read = true;
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}

class NotificationScope extends InheritedWidget {
  const NotificationScope(
      {super.key, required this.center, required super.child});
  final NotificationCenter center;
  static NotificationCenter? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NotificationScope>()?.center;
  @override
  bool updateShouldNotify(NotificationScope oldWidget) =>
      center != oldWidget.center;
}

Future<void> showNotifications(
        BuildContext context, NotificationCenter center) =>
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (context) => Dialog(
        backgroundColor: const Color(0xFFB0E0EF),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 394),
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.9,
            child: ListenableBuilder(
              listenable: center,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(children: [
                  Row(children: [
                    const Expanded(
                        child: Text('Notifications',
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF101C22)))),
                    IconButton(
                        tooltip: 'Mark all as read',
                        onPressed: center.hasUnread ? center.markAllRead : null,
                        icon: const Icon(Icons.check_circle),
                        color: const Color(0xFF20A6D7),
                        constraints:
                            const BoxConstraints(minWidth: 36, minHeight: 48),
                        padding: EdgeInsets.zero),
                    IconButton(
                        tooltip: 'Clear notifications',
                        onPressed: center.items.isEmpty ? null : center.clear,
                        icon: const Icon(Icons.delete),
                        color: const Color(0xFF20A6D7),
                        constraints:
                            const BoxConstraints(minWidth: 36, minHeight: 48),
                        padding: EdgeInsets.zero),
                  ]),
                  Expanded(
                      child: center.items.isEmpty
                          ? const Center(
                              child: Text('No notifications yet',
                                  style: TextStyle(color: Color(0xFF073344))))
                          : ListView.separated(
                              itemCount: center.items.length,
                              separatorBuilder: (_, index) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = center.items[index];
                                return Semantics(
                                  label: item.read
                                      ? 'Read notification'
                                      : 'Unread notification',
                                  child: Material(
                                    color: item.read
                                        ? const Color(0xFF8BD0E8)
                                        : const Color(0xFF55BCE2),
                                    borderRadius: BorderRadius.circular(5),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(5),
                                      onTap: () => center.markRead(item),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 9),
                                        child: Row(children: [
                                          Icon(item.type.icon,
                                              color: item.type.color, size: 36),
                                          const SizedBox(width: 10),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                Text(item.type.title,
                                                    style: TextStyle(
                                                        color: const Color(
                                                            0xFF071E28),
                                                        fontSize: 16,
                                                        fontWeight: item.read
                                                            ? FontWeight.w500
                                                            : FontWeight.bold)),
                                                Text(item.type.message,
                                                    style: const TextStyle(
                                                        color:
                                                            Color(0xFF071E28),
                                                        fontSize: 11)),
                                              ])),
                                          const SizedBox(width: 6),
                                          Text(
                                              MaterialLocalizations.of(context)
                                                  .formatTimeOfDay(
                                                      TimeOfDay.fromDateTime(
                                                          item.time)),
                                              style: const TextStyle(
                                                  color: Color(0xFF071E28),
                                                  fontSize: 10)),
                                        ]),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )),
                  Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close',
                              style: TextStyle(color: Color(0xFF073344))))),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
