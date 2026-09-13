import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'engine.dart';

class Usage {
  const Usage(this.up, this.down);

  final int up, down;
  int get total => up + down;

  Usage operator +(Usage o) => Usage(up + o.up, down + o.down);
}

/// Daily upload/download totals, built from the per-second traffic samples of the core.
class UsageStats {
  static const _key = 'usage_days', _keepDays = 62;
  final Map<String, Usage> _days = {};
  DateTime _lastSave = DateTime.now();

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      map.forEach((k, v) => _days[k] = Usage((v as List)[0] as int, v[1] as int));
    } catch (_) {}
  }

  void add(TrafficStat t) {
    if (t.up == 0 && t.down == 0) return;
    final key = _dayKey(DateTime.now());
    _days[key] = (_days[key] ?? const Usage(0, 0)) + Usage(t.up, t.down);
    if (DateTime.now().difference(_lastSave).inSeconds >= 15) save();
  }

  Future<void> save() async {
    _lastSave = DateTime.now();
    final cutoff = _dayKey(DateTime.now().subtract(const Duration(days: _keepDays)));
    _days.removeWhere((k, _) => k.compareTo(cutoff) < 0);
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode({for (final e in _days.entries) e.key: [e.value.up, e.value.down]}));
  }

  Future<void> reset() async {
    _days.clear();
    await save();
  }

  Usage day(DateTime d) => _days[_dayKey(d)] ?? const Usage(0, 0);

  Usage month(DateTime d) {
    final prefix = _dayKey(d).substring(0, 7);
    return _days.entries.where((e) => e.key.startsWith(prefix)).fold(const Usage(0, 0), (a, e) => a + e.value);
  }

  /// Oldest first, today last.
  List<(DateTime, Usage)> lastDays(int count) {
    final today = DateTime.now();
    return [
      for (var i = count - 1; i >= 0; i--)
        (today.subtract(Duration(days: i)), day(today.subtract(Duration(days: i)))),
    ];
  }
}
