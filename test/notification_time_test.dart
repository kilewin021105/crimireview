// The daily study reminders are due at 9:00 AM and 7:00 PM on the phone's
// own clock. They used to be built in UTC (the scheduler's default), which
// put them at 5 PM and 3 AM in the Philippines.
//
// Run: flutter test test/notification_time_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:crimireview/services/notification_service.dart';

void main() {
  test('later today when the time has not passed yet', () {
    final now = DateTime(2026, 10, 17, 8, 30);
    final at = NotificationService.nextReminderTime(now, 9, 0);
    expect(at.isAtSameMomentAs(DateTime(2026, 10, 17, 9, 0)), isTrue);
  });

  test('tomorrow once the time has passed', () {
    final now = DateTime(2026, 10, 17, 20, 15);
    final at = NotificationService.nextReminderTime(now, 19, 0);
    expect(at.isAtSameMomentAs(DateTime(2026, 10, 18, 19, 0)), isTrue);
  });

  test('tomorrow when it is exactly that time now', () {
    final now = DateTime(2026, 10, 17, 9, 0);
    final at = NotificationService.nextReminderTime(now, 9, 0);
    expect(at.isAtSameMomentAs(DateTime(2026, 10, 18, 9, 0)), isTrue);
  });

  test('the same moment as that hour on the phone clock, not in UTC', () {
    final now = DateTime(2026, 10, 17, 6, 0);
    final at = NotificationService.nextReminderTime(now, 7, 0);
    final localSeven = DateTime(2026, 10, 17, 7, 0);
    expect(at.millisecondsSinceEpoch, localSeven.millisecondsSinceEpoch);
  });
}
