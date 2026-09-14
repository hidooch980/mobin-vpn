import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';

/// Reality SNI retry: when a Reality server keeps failing, its handshake is retried with other camouflage SNIs
/// from a remote list; an SNI that works is remembered per server (host, port and public key).
class RealitySni {
  RealitySni._();

  static const _urls = [
    'https://raw.githubusercontent.com/hidooch980/molidovpn-android/main/remote/reality-sni.txt',
    'https://cdn.jsdelivr.net/gh/hidooch980/molidovpn-android@main/remote/reality-sni.txt',
  ];
  static const _prefsKey = 'reality_sni_v1';
  static const maxTries = 3;

  static Map<String, String> _known = {};
  static bool _loaded = false;
  static List<String>? _list;
  static DateTime? _fetchedAt;

  static Map<String, dynamic>? _reality(Map<String, dynamic> outbound) {
    final tls = outbound['tls'];
    return tls is Map && tls['enabled'] == true && tls['reality'] is Map ? Map<String, dynamic>.from(tls) : null;
  }

  static bool isReality(Map<String, dynamic> outbound) => _reality(outbound) != null;

  static String _key(Map<String, dynamic> outbound) =>
      '${outbound['server']}:${outbound['server_port']}:${(_reality(outbound)?['reality'] as Map?)?['public_key']}';

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
      if (raw != null) _known = Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      _known = {};
    }
  }

  static Future<void> _save() async {
    try {
      await (await SharedPreferences.getInstance()).setString(_prefsKey, jsonEncode(_known));
    } catch (_) {}
  }

  /// SNI that worked for this server before, or null.
  static String? remembered(Map<String, dynamic> outbound) => isReality(outbound) ? _known[_key(outbound)] : null;

  static Future<void> remember(Map<String, dynamic> outbound, String sni) async {
    _known[_key(outbound)] = sni;
    if (_known.length > 200) _known.remove(_known.keys.first);
    await _save();
  }

  static Future<void> forget(Map<String, dynamic> outbound) async {
    if (_known.remove(_key(outbound)) != null) await _save();
  }

  /// Copy of a Reality [outbound] using [sni] as server_name.
  static Map<String, dynamic> withSni(Map<String, dynamic> outbound, String sni) {
    final tls = _reality(outbound);
    return tls == null ? outbound : {...outbound, 'tls': {...tls, 'server_name': sni}};
  }

  /// Up to [maxTries] SNIs from the remote list, different from the outbound's own. Empty when unreachable.
  static Future<List<String>> candidates(Map<String, dynamic> outbound) async {
    final own = _reality(outbound)?['server_name'];
    final list = await _fetch();
    return list.where((s) => s != own).take(maxTries).toList();
  }

  static Future<List<String>> _fetch() async {
    final cached = _list;
    final at = _fetchedAt;
    if (cached != null && at != null && DateTime.now().difference(at) < const Duration(hours: 6)) return cached;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      for (final url in _urls) {
        try {
          final res = await (await client.getUrl(Uri.parse(url))).close().timeout(const Duration(seconds: 10));
          if (res.statusCode != 200) {
            await res.drain<void>();
            continue;
          }
          final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 10));
          final names = [
            for (final line in const LineSplitter().convert(body))
              if (line.trim().isNotEmpty && !line.trim().startsWith('#') && !line.trim().contains(' ')) line.trim(),
          ];
          if (names.isEmpty) continue;
          _list = names;
          _fetchedAt = DateTime.now();
          return names;
        } catch (_) {}
      }
      AppLog.add('reality sni: list not reachable');
      return cached ?? const [];
    } finally {
      client.close(force: true);
    }
  }
}
