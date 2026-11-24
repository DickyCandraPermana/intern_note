const List<String> indonesianMonths = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

const List<String> indonesianShortMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

const List<String> indonesianDays = [
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

const List<String> indonesianShortDays = [
  'Sen',
  'Sel',
  'Rab',
  'Kam',
  'Jum',
  'Sab',
  'Min',
];

const List<String> _englishMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const List<String> _englishDays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String formatIsoDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String normalizeIsoDate(String raw) {
  final trimmed = raw.trim();
  final match = RegExp(r'^(\d{4}-\d{2}-\d{2})').firstMatch(trimmed);
  if (match != null) {
    return match.group(1)!;
  }
  final parsed = DateTime.tryParse(trimmed);
  if (parsed != null) {
    return formatIsoDate(parsed);
  }
  return trimmed.length >= 10 ? trimmed.substring(0, 10) : trimmed;
}

String formatIndonesianDate(DateTime date) {
  return '${date.day} ${indonesianMonths[date.month - 1]} ${date.year}';
}

String formatIndonesianShortDate(DateTime date) {
  return '${indonesianShortDays[date.weekday - 1]}, ${date.day} ${indonesianShortMonths[date.month - 1]}';
}

String formatIndonesianLongDayDate(DateTime date) {
  return '${indonesianDays[date.weekday - 1]}, ${date.day} ${indonesianShortMonths[date.month - 1]} ${date.year}';
}

String formatCycleRangeLabel(DateTime start, DateTime end) {
  final startLabel = '${start.day} ${indonesianShortMonths[start.month - 1]}';
  final endLabel = '${end.day} ${indonesianShortMonths[end.month - 1]} ${end.year}';
  if (start.year != end.year) {
    return '$startLabel ${start.year} - $endLabel';
  }
  return '$startLabel - $endLabel';
}

String formatExcelDisplayDate(DateTime date) {
  return '${_englishDays[date.weekday - 1]}, ${_englishMonths[date.month - 1]} ${date.day}, ${date.year}';
}

String extractFirstName(String fullName, {String fallback = 'Consultant'}) {
  final trimmed = fullName.trim();
  if (trimmed.isEmpty) return fallback;
  final first = trimmed.split(RegExp(r'\s+')).first;
  return first.isEmpty ? fallback : first;
}
