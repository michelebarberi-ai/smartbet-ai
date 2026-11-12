/// Calendar-day window shared by AutoSchedina's fetch and serialization.
/// Days refer to Europe/Rome, not 24-hour UTC periods (DST aware).
class GoalVdLineRomeDayWindow {
  const GoalVdLineRomeDayWindow._();

  static DateTime _romeDate(DateTime instant) {
    final utc = instant.toUtc();
    DateTime lastSunday(int month) {
      final lastDay = DateTime.utc(utc.year, month + 1, 0);
      return DateTime.utc(utc.year, month,
          lastDay.day - (lastDay.weekday % DateTime.daysPerWeek), 1);
    }
    final dst = !utc.isBefore(lastSunday(3)) &&
        utc.isBefore(lastSunday(10));
    final rome = utc.add(Duration(hours: dst ? 2 : 1));
    return DateTime.utc(rome.year, rome.month, rome.day);
  }

  static List<DateTime> dates({
    required DateTime now,
    required int windowDays,
  }) {
    if (windowDays < 1 || windowDays > 3) {
      throw ArgumentError.value(windowDays, 'windowDays');
    }
    final first = _romeDate(now);
    return List<DateTime>.generate(windowDays,
        (offset) => DateTime.utc(first.year, first.month, first.day + offset));
  }

  static bool includes({
    required DateTime kickoff,
    required DateTime now,
    required int windowDays,
  }) {
    if (!kickoff.toUtc().isAfter(now.toUtc())) return false;
    final localDay = _romeDate(kickoff);
    return dates(now: now, windowDays: windowDays).contains(localDay);
  }
}
