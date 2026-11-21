/// Review-screen text helpers, ported from `src/core/review/index.ts`.
library;

import '../schema/cards.dart';

const _minute = 60000;
const _hour = 60 * _minute;
const _day = 24 * _hour;

String _trim(double v) {
  if (v >= 10) return '${v.round()}';
  final s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Short interval label for a grade button: "<1m", "10m", "3h", "4d", "2.5mo", "1.2y".
String formatInterval(int ms) {
  if (ms < _minute) return '<1m';
  if (ms < _hour) return '${(ms / _minute).round()}m';
  if (ms < _day) return '${(ms / _hour).round()}h';
  final days = ms / _day;
  if (days < 30) return '${days.round()}d';
  if (days < 365) return '${_trim(days / 30)}mo';
  return '${_trim(days / 365)}y';
}

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _months = [
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

String _time(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// When a later card is due, in words: "in 12 minutes", "tomorrow at 9:00 AM".
String formatNextDue(int due, int now) {
  final diff = due - now;
  if (diff < _hour) {
    final minutes = (diff / _minute).round().clamp(1, 60);
    return 'in $minutes minute${minutes == 1 ? '' : 's'}';
  }
  final d = DateTime.fromMillisecondsSinceEpoch(due);
  final n = DateTime.fromMillisecondsSinceEpoch(now);
  final days =
      DateTime(
        d.year,
        d.month,
        d.day,
      ).difference(DateTime(n.year, n.month, n.day)).inHours /
      24;
  final dayCount = days.round();
  final time = _time(d);
  if (dayCount == 0) return 'today at $time';
  if (dayCount == 1) return 'tomorrow at $time';
  if (dayCount < 7) return '${_weekdays[d.weekday - 1]} at $time';
  return 'on ${_months[d.month - 1]} ${d.day}';
}

enum PartKind { tool, flag, arg, blank }

class Part {
  const Part(this.kind, this.text);
  final PartKind kind;
  final String text;
}

final _flagWord = RegExp(r'^--?[^\s-]');
final _argWord = RegExp(r'^<.+>$');

/// Splits a command into parts for display.
List<Part> commandParts(String command) {
  final words = command
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  return [
    for (final (i, word) in words.indexed)
      if (word.contains(clozeBlank))
        Part(PartKind.blank, word.replaceFirst(clozeBlank, ''))
      else if (i == 0)
        Part(PartKind.tool, word)
      else if (_flagWord.hasMatch(word))
        Part(PartKind.flag, word)
      else if (_argWord.hasMatch(word))
        Part(PartKind.arg, word)
      else
        Part(PartKind.tool, word),
  ];
}
