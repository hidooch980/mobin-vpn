import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "What's new" after an update: shown once when the installed version differs from the last one seen.
class WhatsNew {
  const WhatsNew(this.version, this.items);

  final String version;
  final List<String> items;

  static const _key = 'last_seen_version';

  /// Null on fresh install or when nothing changed. Never throws.
  static Future<WhatsNew?> check() async {
    try {
      final version = (await PackageInfo.fromPlatform()).version;
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(_key) ?? '';
      await prefs.setString(_key, version);
      if (last.isEmpty || last == version) return null;
      var items = <String>[];
      try {
        items = await _fetch(version);
      } catch (_) {}
      if (items.isEmpty) items = ['نسخهٔ $version نصب شد', 'بهبود پایداری و سرعت'];
      return WhatsNew(version, items);
    } catch (_) {
      return null;
    }
  }

  static Future<List<String>> _fetch(String version) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse('https://molido-sub.hidooch980.workers.dev/app/changelog.json?v=$version'));
      final res = await req.close().timeout(const Duration(seconds: 10));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return [];
      final list = (jsonDecode(body) as Map<String, dynamic>)['items'] as List? ?? [];
      final platform = Platform.isAndroid ? 'android' : 'windows';
      return [
        for (final i in list.cast<Map<String, dynamic>>())
          if (i['platform'] == null || i['platform'] == 'all' || i['platform'] == platform) '${i['text']}',
      ];
    } finally {
      client.close(force: true);
    }
  }
}
