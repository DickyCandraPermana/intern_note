import 'package:flutter_test/flutter_test.dart';
import 'package:intern_noter/utils/billing_cycle.dart';
import 'package:intern_noter/utils/date_formatters.dart';

void main() {
  test('cycleFor handles 25-to-24 boundary on 24th vs 25th', () {
    final nov = BillingCycleHelper.cycleFor(DateTime(2026, 11, 24), cutoffDay: 24);
    expect(formatIsoDate(nov.start), '2026-10-25');
    expect(formatIsoDate(nov.end), '2026-11-24');
    expect(nov.monthNameIndo, 'November');

    final dec = BillingCycleHelper.cycleFor(DateTime(2026, 11, 25), cutoffDay: 24);
    expect(formatIsoDate(dec.start), '2026-11-25');
    expect(formatIsoDate(dec.end), '2026-12-24');
    expect(dec.monthNameIndo, 'Desember');
  });

  test('cycleFor handles Dec-Jan year rollover and Feb 28/29 leap transitions', () {
    final jan = BillingCycleHelper.cycleFor(DateTime(2026, 12, 26), cutoffDay: 24);
    expect(formatIsoDate(jan.start), '2026-12-25');
    expect(formatIsoDate(jan.end), '2027-01-24');
    expect(formatCycleRangeLabel(jan.start, jan.end), '25 Des 2026 - 24 Jan 2027');

    final marNonLeap = BillingCycleHelper.cycleFor(DateTime(2026, 3, 10), cutoffDay: 28);
    expect(formatIsoDate(marNonLeap.start), '2026-03-01');
    expect(formatIsoDate(marNonLeap.end), '2026-03-28');

    final marLeap = BillingCycleHelper.cycleFor(DateTime(2024, 3, 10), cutoffDay: 28);
    expect(formatIsoDate(marLeap.start), '2024-02-29');
    expect(formatIsoDate(marLeap.end), '2024-03-28');
  });

  test('missingWeekdays excludes weekends, logged dates, and future days', () {
    final cycle = BillingCycleHelper.cycleForYearMonth(2026, 11, cutoffDay: 24);
    // 2026-10-25 (Sun), 2026-10-26 (Mon), 2026-10-27 (Tue), 2026-10-28 (Wed)
    final missing = BillingCycleHelper.missingWeekdays(
      cycle,
      ['2026-10-26'],
      asOf: DateTime(2026, 10, 28),
    );
    expect(missing.map(formatIsoDate).toList(), ['2026-10-27', '2026-10-28']);
  });

  test('Indonesian and Excel date formatters are locale-independent', () {
    expect(formatIndonesianDate(DateTime(2026, 11, 24)), '24 November 2026');
    expect(formatIndonesianShortDate(DateTime(2026, 11, 24)), 'Sel, 24 Nov');
    expect(formatIndonesianLongDayDate(DateTime(2026, 11, 24)), 'Selasa, 24 Nov 2026');
    expect(formatExcelDisplayDate(DateTime(2026, 11, 24)), 'Tuesday, November 24, 2026');
    expect(normalizeIsoDate('2026-11-24T13:45:00.000'), '2026-11-24');
    expect(extractFirstName('Dicky Candra Permana'), 'Dicky');
    expect(extractFirstName('   '), 'Consultant');
  });

  test('previousCycle, nextCycle, contains, and expectedWeekdaysCount work cleanly', () {
    final nov = BillingCycleHelper.cycleForYearMonth(2026, 11, cutoffDay: 24);
    final oct = BillingCycleHelper.previousCycle(nov, cutoffDay: 24);
    expect(oct.cycleYear, 2026);
    expect(oct.cycleMonth, 10);
    final dec = BillingCycleHelper.nextCycle(nov, cutoffDay: 24);
    expect(dec.cycleYear, 2026);
    expect(dec.cycleMonth, 12);

    expect(nov.contains(DateTime(2026, 10, 25)), isTrue);
    expect(nov.contains(DateTime(2026, 11, 24, 23, 59)), isTrue);
    expect(nov.contains(DateTime(2026, 10, 24)), isFalse);
    expect(nov.contains(DateTime(2026, 11, 25)), isFalse);
    expect(BillingCycleHelper.expectedWeekdaysCount(nov), 22);
  });
}
