import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Health of one server on one network, learned by the background scanner.
class ServerHealth {
  ServerHealth({this.lastOk, this.ms, this.fails = 0, this.badUntil});

  DateTime? lastOk;
  int? ms;
  int fails;
  DateTime? badUntil;

  factory ServerHealth.fromJson(Map<String, dynamic> j) => ServerHealth(
        lastOk: j['o'] is int ? DateTime.fromMillisecondsSinceEpoch(j['o'] as int) : null,
        ms: j['m'] is int ? j['m'] as int : null,
        fails: j['f'] is int ? j['f'] as int : 0,
        badUntil: j['b'] is int ? DateTime.fromMillisecondsSinceEpoch(j['b'] as int) : null,
      );

  Map<String, dynamic> toJson() => {
        if (lastOk != null) 'o': lastOk!.millisecondsSinceEpoch,
        if (ms != null) 'm': ms,
        if (fails > 0) 'f': fails,
        if (badUntil != null) 'b': badUntil!.millisecondsSinceEpoch,
      };
}

/// Per-network (network + ISP bucket) memory of which servers work on the user's own internet.
/// Recent successes rank first; [failLimit] consecutive failures deprioritise a server for [badFor].
class HealthBook {
  static const failLimit = 3;
  static const badFor = Duration(hours: 6);
  static const recent = Duration(hours: 3);
  static const _forget = Duration(days: 7);
  static const _prefsKey = 'bg_scan_health_v1';

  /// network key -> server key -> health.
  final Map<String, Map<String, ServerHealth>> _byNet = {};

  void record(String net, String server, int delay, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final h = _byNet.putIfAbsent(net, () => {}).putIfAbsent(server, ServerHealth.new);
    if (delay > 0) {
      h
        ..lastOk = t
        ..ms = delay
        ..fails = 0
        ..badUntil = null;
    } else {
      h.fails++;
      if (h.fails >= failLimit) h.badUntil = t.add(badFor);
    }
  }

  ServerHealth? health(String net, String server) => _byNet[net]?[server];

  bool isDeprioritised(String net, String server, {DateTime? now}) =>
      _byNet[net]?[server]?.badUntil?.isAfter(now ?? DateTime.now()) ?? false;

  /// 0 = recent success, 1 = unknown / stale, 2 = deprioritised.
  int tier(String net, String server, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final h = _byNet[net]?[server];
    if (h == null) return 1;
    if (h.badUntil?.isAfter(t) ?? false) return 2;
    final ok = h.lastOk;
    return ok != null && t.difference(ok) < recent ? 0 : 1;
  }

  /// Stable reorder of [items]: recent successes (fastest first), then the rest in their order, deprioritised last.
  List<T> order<T>(String net, List<T> items, String Function(T) keyOf, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final indexed = [
      for (final (i, item) in items.indexed) (i, item, tier(net, keyOf(item), now: t), _byNet[net]?[keyOf(item)]?.ms ?? 0),
    ]..sort((a, b) {
        final byTier = a.$3.compareTo(b.$3);
        if (byTier != 0) return byTier;
        if (a.$3 == 0) {
          final byMs = a.$4.compareTo(b.$4);
          if (byMs != 0) return byMs;
        }
        return a.$1.compareTo(b.$1);
      });
    return [for (final e in indexed) e.$2];
  }

  void prune({DateTime? now}) {
    final t = now ?? DateTime.now();
    for (final net in _byNet.values) {
      net.removeWhere((_, h) {
        final last = [h.lastOk, h.badUntil].whereType<DateTime>().fold<DateTime?>(
            null, (a, b) => a == null || b.isAfter(a) ? b : a);
        return last == null ? h.fails == 0 : t.difference(last) > _forget;
      });
    }
    _byNet.removeWhere((_, m) => m.isEmpty);
  }

  String toJsonString() =>
      jsonEncode({for (final e in _byNet.entries) e.key: {for (final s in e.value.entries) s.key: s.value.toJson()}});

  void loadJsonString(String text) {
    _byNet.clear();
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return;
      for (final net in decoded.entries) {
        final servers = net.value;
        if (servers is! Map<String, dynamic>) continue;
        _byNet[net.key] = {
          for (final s in servers.entries)
            if (s.value is Map<String, dynamic>) s.key: ServerHealth.fromJson(s.value as Map<String, dynamic>),
        };
      }
    } catch (_) {
      _byNet.clear();
    }
  }

  Future<void> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
    if (raw != null) loadJsonString(raw);
  }

  Future<void> save() async {
    prune();
    await (await SharedPreferences.getInstance()).setString(_prefsKey, toJsonString());
  }
}

/// Sliding one-hour budget for anonymous reports sent by the background scanner.
class HourlyBudget {
  HourlyBudget(this.limit);

  final int limit;
  final List<DateTime> _sent = [];

  /// How many of [wanted] may be sent now; those are counted as sent.
  int take(int wanted, {DateTime? now}) {
    final t = now ?? DateTime.now();
    _sent.removeWhere((at) => t.difference(at) >= const Duration(hours: 1));
    final n = wanted.clamp(0, limit - _sent.length);
    for (var i = 0; i < n; i++) {
      _sent.add(t);
    }
    return n;
  }
}
