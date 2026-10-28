typedef Clock = DateTime Function();
String civilDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
DateTime civilUtc(DateTime d) => DateTime.utc(d.year, d.month, d.day);
int dayIndex(DateTime d) =>
    civilUtc(d).difference(DateTime.utc(2026, 1, 1)).inDays;
bool validDate(String s) {
  final d = DateTime.tryParse(s);
  return d != null &&
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s) &&
      civilDate(d) == s;
}
