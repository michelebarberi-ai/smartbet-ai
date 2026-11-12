import 'package:flutter_test/flutter_test.dart';
import 'package:smartbet_ai_new/services/goalvdline_rome_day_window.dart';

void main() {
  test('P20.4 inclusive Rome days cover 1, 2 or 3 calendar dates', () {
    final now = DateTime.utc(2026, 11, 12, 10);
    final days = GoalVdLineRomeDayWindow.dates(now: now, windowDays: 3);
    expect(days.map((date) => date.toIso8601String().substring(0, 10)),
        ['2026-11-12', '2026-11-13', '2026-11-14']);
    expect(GoalVdLineRomeDayWindow.includes(
      kickoff: DateTime.utc(2026, 11, 14, 19), now: now, windowDays: 3), isTrue);
    expect(GoalVdLineRomeDayWindow.includes(
      kickoff: DateTime.utc(2026, 11, 15, 19), now: now, windowDays: 3), isFalse);
    expect(GoalVdLineRomeDayWindow.includes(
      kickoff: DateTime.utc(2026, 11, 13, 19), now: now, windowDays: 1), isFalse);
  });

  test('P20.4 Rome DST boundaries are calendar-safe', () {
    final start = DateTime.utc(2027, 3, 27, 23, 30);
    final days = GoalVdLineRomeDayWindow.dates(now: start, windowDays: 3);
    expect(days.map((d) => d.toIso8601String().substring(0, 10)),
        ['2027-03-28', '2027-03-29', '2027-03-30']);
    final autumn = DateTime.utc(2027, 10, 30, 23, 30);
    expect(GoalVdLineRomeDayWindow.dates(now: autumn, windowDays: 3)
        .map((d) => d.toIso8601String().substring(0, 10)),
        ['2027-10-31', '2027-11-01', '2027-11-02']);
  });
}
