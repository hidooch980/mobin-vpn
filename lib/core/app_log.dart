import 'package:flutter/foundation.dart';

/// In-memory diagnostic log shown in "گزارش خطا" so users can copy and send it.
class AppLog {
  static const _max = 500;
  static final List<String> _lines = [];

  static void add(String message) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    _lines.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)}  $message');
    if (_lines.length > _max) _lines.removeRange(0, _lines.length - _max);
    debugPrint('[mobin] $message');
  }

  static String dump() => _lines.join('\n');

  static void clear() => _lines.clear();
}
