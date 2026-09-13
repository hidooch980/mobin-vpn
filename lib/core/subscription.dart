import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'server.dart';

class SubscriptionData {
  const SubscriptionData(this.servers, this.updatedAt);

  final List<Server> servers;
  final DateTime updatedAt;
}

/// Downloads the tested server list from the vpn-sub repo, with CDN mirrors and an offline cache.
class SubscriptionRepository {
  /// Light list (40 servers) for iPhone/Hiddify — the full list can exceed iOS VPN memory limits.
  static const shareLink = 'https://raw.githubusercontent.com/hidooch980/vpn-sub/sub/lite_base64.txt';

  static const _mirrors = [
    'https://raw.githubusercontent.com/hidooch980/vpn-sub/sub/sub.txt',
    'https://cdn.jsdelivr.net/gh/hidooch980/vpn-sub@sub/sub.txt',
    'https://fastly.jsdelivr.net/gh/hidooch980/vpn-sub@sub/sub.txt',
  ];
  static const _textKey = 'sub_text', _timeKey = 'sub_time';

  Future<SubscriptionData?> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString(_textKey);
    final time = prefs.getInt(_timeKey);
    if (text == null || time == null) return null;
    final servers = parseSubscription(text);
    return servers.isEmpty ? null : SubscriptionData(servers, DateTime.fromMillisecondsSinceEpoch(time));
  }

  Future<SubscriptionData> fetch() async {
    for (final url in _mirrors) {
      try {
        final text = await _get(url);
        final servers = parseSubscription(text);
        if (servers.isEmpty) continue;
        final now = DateTime.now();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_textKey, text);
        await prefs.setInt(_timeKey, now.millisecondsSinceEpoch);
        return SubscriptionData(servers, now);
      } catch (_) {
        continue;
      }
    }
    throw const SocketException('all subscription mirrors failed');
  }

  Future<String> _get(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final bust = DateTime.now().millisecondsSinceEpoch ~/ 60000;
      final req = await client.getUrl(Uri.parse('$url?t=$bust'));
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      return await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 30));
    } finally {
      client.close(force: true);
    }
  }
}
