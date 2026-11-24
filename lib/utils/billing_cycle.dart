import 'date_formatters.dart';

class BillingCycle {
  final DateTime start;
  final DateTime end;
  final int cycleYear;
  final int cycleMonth;

  const BillingCycle({
    required this.start,
    required this.end,
    required this.cycleYear,
    required this.cycleMonth,
  });

  bool contains(DateTime date) {
    final target = DateTime(date.year, date.month, date.day);
    final startDate = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);
    return !target.isBefore(startDate) && !target.isAfter(endDate);
  }

  String get monthNameIndo => indonesianMonths[cycleMonth - 1];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BillingCycle &&
        other.start == start &&
        other.end == end &&
        other.cycleYear == cycleYear &&
        other.cycleMonth == cycleMonth;
  }

  @override
  int get hashCode => Object.hash(start, end, cycleYear, cycleMonth);
}

class BillingCycleHelper {
  static BillingCycle cycleFor(DateTime ref, {int cutoffDay = 24}) {
    final clamped = cutoffDay.clamp(1, 28);
    if (ref.day <= clamped) {
      return cycleForYearMonth(ref.year, ref.month, cutoffDay: clamped);
    }
    final nextMonth = DateTime(ref.year, ref.month + 1, 1);
    return cycleForYearMonth(nextMonth.year, nextMonth.month, cutoffDay: clamped);
  }

  static BillingCycle cycleForYearMonth(
    int year,
    int month, {
    int cutoffDay = 24,
  }) {
    final clamped = cutoffDay.clamp(1, 28);
    final target = DateTime(year, month, 1);
    final end = DateTime(target.year, target.month, clamped);
    final prevMonth = DateTime(target.year, target.month - 1, 1);
    final start = DateTime(prevMonth.year, prevMonth.month, clamped + 1);
    return BillingCycle(
      start: start,
      end: end,
      cycleYear: target.year,
      cycleMonth: target.month,
    );
  }

  static BillingCycle previousCycle(BillingCycle cycle, {int cutoffDay = 24}) {
    return cycleForYearMonth(
      cycle.cycleYear,
      cycle.cycleMonth - 1,
      cutoffDay: cutoffDay,
    );
  }

  static BillingCycle nextCycle(BillingCycle cycle, {int cutoffDay = 24}) {
    return cycleForYearMonth(
      cycle.cycleYear,
      cycle.cycleMonth + 1,
      cutoffDay: cutoffDay,
    );
  }

  static List<DateTime> missingWeekdays(
    BillingCycle cycle,
    Iterable<String> loggedIsoDates, {
    DateTime? asOf,
  }) {
    final loggedSet = loggedIsoDates.map(normalizeIsoDate).toSet();
    final ref = asOf ?? DateTime.now();
    final asOfDate = DateTime(ref.year, ref.month, ref.day);
    final startDate = DateTime(cycle.start.year, cycle.start.month, cycle.start.day);
    final endDate = DateTime(cycle.end.year, cycle.end.month, cycle.end.day);
    final upperBound = asOfDate.isBefore(endDate) ? asOfDate : endDate;

    if (upperBound.isBefore(startDate)) {
      return const [];
    }

    final missing = <DateTime>[];
    var cursor = startDate;
    while (!cursor.isAfter(upperBound)) {
      if (cursor.weekday >= DateTime.monday &&
          cursor.weekday <= DateTime.friday &&
          !loggedSet.contains(formatIsoDate(cursor))) {
        missing.add(cursor);
      }
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    return missing;
  }

  static int expectedWeekdaysCount(BillingCycle cycle) {
    var count = 0;
    var cursor = DateTime(cycle.start.year, cycle.start.month, cycle.start.day);
    final endDate = DateTime(cycle.end.year, cycle.end.month, cycle.end.day);
    while (!cursor.isAfter(endDate)) {
      if (cursor.weekday >= DateTime.monday && cursor.weekday <= DateTime.friday) {
        count++;
      }
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    return count;
  }
}
