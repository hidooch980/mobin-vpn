import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';
import 'engine.dart';
import 'network_info.dart';
import 'server.dart';
import 'singbox_outbound.dart';

/// Clean Cloudflare IP: for CDN servers (ws/httpupgrade + TLS behind Cloudflare) find Cloudflare edge IPs
/// that answer a TLS handshake fast on the user's own network, and dial those instead of the DNS answer.
/// SNI and the WebSocket Host stay the server's domain, so Cloudflare still routes to the same origin.
class CleanIp {
  CleanIp._();

  static const _prefsKey = 'cf_clean_v1';
  static const _keep = 5, _sample = 64, _concurrency = 16;
  static const _timeout = Duration(milliseconds: 1500);
  static const rescanEvery = Duration(minutes: 30);

  /// Cloudflare IPv4 ranges (https://www.cloudflare.com/ips-v4).
  static const ranges = [
    '173.245.48.0/20', '103.21.244.0/22', '103.22.200.0/22', '103.31.4.0/22', '141.101.64.0/18',
    '108.162.192.0/18', '190.93.240.0/20', '188.114.96.0/20', '197.234.240.0/22', '198.41.128.0/17',
    '162.158.0.0/15', '104.16.0.0/13', '104.24.0.0/14', '172.64.0.0/13', '131.0.72.0/22',
  ];

  /// Cloudflare anycast IPv6 blocks sampled when the PC has global IPv6: 2606:4700:3030::/48 … 2606:4700:3037::/48.
  static const _v6Prefixes = 8, _sampleV6 = 24;

  static final _hostIsCf = <String, bool>{};
  static final _random = math.Random();

  /// network key -> {'ts': ms since epoch, 'base': handshake ms of the normal DNS answer (-1 failed), 'ips': [[ip, ms]]}
  static Map<String, dynamic> _cache = {};
  static bool _loaded = false, _scanning = false;
  static String? _network;

  static int _toInt(String ip) => ip.split('.').fold(0, (a, p) => (a << 8) | int.parse(p));
  static String _toIp(int v) => [24, 16, 8, 0].map((s) => (v >> s) & 255).join('.');

  static bool isCloudflare(String ip) {
    final addr = InternetAddress.tryParse(ip);
    if (addr == null || addr.type != InternetAddressType.IPv4) return false;
    final v = _toInt(ip);
    for (final r in ranges) {
      final slash = r.indexOf('/');
      final bits = int.parse(r.substring(slash + 1));
      final mask = (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF;
      if ((v & mask) == (_toInt(r.substring(0, slash)) & mask)) return true;
    }
    return false;
  }

  /// A CDN-style outbound that may dial a different Cloudflare IP: TLS (not Reality), ws/httpupgrade, domain server.
  static bool eligible(Map<String, dynamic> outbound) {
    final tls = outbound['tls'];
    final transport = outbound['transport'];
    final server = outbound['server'];
    return server is String &&
        InternetAddress.tryParse(server) == null &&
        tls is Map &&
        tls['enabled'] == true &&
        tls['reality'] == null &&
        transport is Map &&
        (transport['type'] == 'ws' || transport['type'] == 'httpupgrade');
  }

  /// Windows: default gateway (plus ISP bucket) identifies the network; elsewhere the normal network key.
  static Future<String> networkKey() async {
    final op = NetworkInfo.operatorBucket ?? '';
    if (Platform.isWindows) {
      try {
        final r = await Process.run('route', ['print', '-4', '0.0.0.0']).timeout(const Duration(seconds: 3));
        final m = RegExp(r'^\s*0\.0\.0\.0\s+0\.0\.0\.0\s+(\d+\.\d+\.\d+\.\d+)', multiLine: true).firstMatch('${r.stdout}');
        if (m != null) return 'gw:${m.group(1)}|$op';
      } catch (_) {}
    }
    return '${await NetworkInfo.networkKey()}|$op';
  }

  static Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
      if (raw != null) _cache = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      _cache = {};
    }
  }

  static Future<void> _save() async {
    try {
      await (await SharedPreferences.getInstance()).setString(_prefsKey, jsonEncode(_cache));
    } catch (_) {}
  }

  /// Best clean IP for this outbound's domain on the current network, or null (not Cloudflare / not faster).
  static String? bestFor(String host) {
    if (_hostIsCf[host] != true) return null;
    final entry = _cache[_network];
    if (entry is! Map) return null;
    final ts = entry['ts'];
    if (ts is! int || DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts)) > const Duration(hours: 6)) {
      return null;
    }
    final ips = entry['ips'];
    if (ips is! List || ips.isEmpty) return null;
    // IPv6 winners are only usable while this PC still has global IPv6.
    final best = ips.firstWhere((e) => e is List && e.isNotEmpty && (NetworkInfo.globalIpv6 || !'${e[0]}'.contains(':')),
        orElse: () => null);
    if (best is! List || best.length < 2) return null;
    final base = entry['base'];
    final ms = best[1];
    // Only worth it when the normal address is blocked/slow: at least 20 % faster than the DNS answer.
    if (base is int && base > 0 && ms is int && ms > base * 0.8) return null;
    return best[0] as String?;
  }

  /// Copy of [outbound] dialing the best clean IP; SNI and Host header keep the original domain.
  static Map<String, dynamic> apply(Map<String, dynamic> outbound) {
    if (!eligible(outbound)) return outbound;
    final host = outbound['server'] as String;
    final ip = bestFor(host);
    if (ip == null) return outbound;
    final tls = Map<String, dynamic>.from(outbound['tls'] as Map);
    final serverName = tls['server_name'];
    if (serverName is! String || serverName.isEmpty) tls['server_name'] = host;
    final transport = Map<String, dynamic>.from(outbound['transport'] as Map);
    if (transport['type'] == 'ws') {
      final headers = Map<String, dynamic>.from((transport['headers'] as Map?) ?? const {});
      final h = headers['Host'];
      if (h is! String || h.isEmpty) headers['Host'] = host;
      transport['headers'] = headers;
    } else if (transport['type'] == 'httpupgrade') {
      final h = transport['host'];
      if (h is! String || h.isEmpty) transport['host'] = host;
    }
    return {...outbound, 'server': ip, 'tls': tls, 'transport': transport};
  }

  /// A clean IP failed in a real connection: drop it so the next attempt uses another one (or the DNS answer).
  static void markBad(String ip) {
    final entry = _cache[_network];
    if (entry is! Map) return;
    final ips = entry['ips'];
    if (ips is List) ips.removeWhere((e) => e is List && e.isNotEmpty && e[0] == ip);
    unawaited(_save());
  }

  static Future<int> _handshake(String ip, String sni) async {
    final watch = Stopwatch()..start();
    Socket? raw;
    SecureSocket? secure;
    try {
      raw = await Socket.connect(ip, 443, timeout: _timeout);
      final left = _timeout - watch.elapsed;
      if (left <= Duration.zero) return -1;
      secure = await SecureSocket.secure(raw, host: sni, onBadCertificate: (_) => true).timeout(left);
      return watch.elapsedMilliseconds;
    } catch (_) {
      return -1;
    } finally {
      if (secure != null) {
        secure.destroy();
      } else {
        raw?.destroy();
      }
    }
  }

  /// Random host in one of the Cloudflare /48 blocks 2606:4700:3030..3037.
  static String _randomIpV6() {
    final hextets = [for (var i = 0; i < 5; i++) _random.nextInt(0x10000).toRadixString(16)];
    if (hextets.last == '0') hextets[4] = '1';
    return '2606:4700:${(0x3030 + _random.nextInt(_v6Prefixes)).toRadixString(16)}:${hextets.join(':')}';
  }

  static String _randomIp() {
    final r = ranges[_random.nextInt(ranges.length)];
    final slash = r.indexOf('/');
    final size = 1 << (32 - int.parse(r.substring(slash + 1)));
    // Skip network/broadcast-looking addresses (.0 / .255).
    for (;;) {
      final ip = _toIp(_toInt(r.substring(0, slash)) + _random.nextInt(size));
      if (!ip.endsWith('.0') && !ip.endsWith('.255')) return ip;
    }
  }

  /// Background tick: classifies CDN hosts of [servers] and rescans on a new network or every 30 min.
  /// The caller must only allow it while the PC's own traffic does not go through the tunnel (no TUN).
  static Future<void> tick(List<Server> servers) async {
    if (_scanning) return;
    _scanning = true;
    try {
      await _load();
      final key = await networkKey();
      final changed = key != _network;
      _network = key;

      final hosts = <String, String>{}; // server domain -> SNI
      for (final s in servers.take(60)) {
        final o = parseOutbound(s.uri);
        if (o == null || !eligible(o)) continue;
        final host = o['server'] as String;
        final sni = (o['tls'] as Map)['server_name'];
        hosts.putIfAbsent(host, () => sni is String && sni.isNotEmpty ? sni : host);
      }
      final unknown = hosts.keys.where((h) => !_hostIsCf.containsKey(h)).toList();
      final baseline = <String, String>{}; // host -> resolved IP
      await runPool(unknown.length, 8, (i) async {
        final host = unknown[i];
        try {
          final found = await InternetAddress.lookup(host, type: InternetAddressType.IPv4).timeout(const Duration(seconds: 3));
          final ip = found.isEmpty ? null : found.first.address;
          _hostIsCf[host] = ip != null && isCloudflare(ip);
          if (ip != null && _hostIsCf[host]!) baseline[host] = ip;
        } catch (_) {
          // Lookup failed (maybe DNS-blocked): decide on a later tick.
        }
        return 0;
      });
      final cfHost = hosts.keys.where((h) => _hostIsCf[h] == true).firstOrNull;
      if (cfHost == null) return;

      final entry = _cache[key];
      final ts = entry is Map ? entry['ts'] : null;
      final stale = ts is! int || DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ts)) > rescanEvery;
      if (!changed && !stale) return;
      if (!stale && entry is Map && (entry['ips'] as List?)?.isNotEmpty == true) return; // new network key but fresh cache

      final sni = hosts[cfHost]!;
      final ipv6 = await NetworkInfo.detectIpv6();
      final candidates = {
        for (var i = 0; i < _sample; i++) _randomIp(),
        if (ipv6)
          for (var i = 0; i < _sampleV6; i++) _randomIpV6(),
      }.toList();
      // Keep previously good IPs in the race so a stable winner is not lost to sampling.
      if (entry is Map && entry['ips'] is List) {
        for (final e in entry['ips'] as List) {
          if (e is List && e.isNotEmpty && e[0] is String && !candidates.contains(e[0])) candidates.add(e[0] as String);
        }
      }
      String? baseIp = baseline[cfHost];
      if (baseIp == null) {
        try {
          final found = await InternetAddress.lookup(cfHost, type: InternetAddressType.IPv4).timeout(const Duration(seconds: 3));
          baseIp = found.isEmpty ? null : found.first.address;
        } catch (_) {}
      }
      final base = baseIp == null ? -1 : await _handshake(baseIp, sni);
      final results = await runPool(candidates.length, _concurrency, (i) => _handshake(candidates[i], sni));
      final good = [
        for (var i = 0; i < candidates.length; i++)
          if (results[i] > 0) [candidates[i], results[i]],
      ]..sort((a, b) => (a[1] as int).compareTo(b[1] as int));
      _cache[key] = {'ts': DateTime.now().millisecondsSinceEpoch, 'base': base, 'ips': good.take(_keep).toList()};
      // Keep the cache small: at most 8 networks.
      if (_cache.length > 8) {
        final oldest = _cache.entries.toList()
          ..sort((a, b) => ((a.value as Map)['ts'] as int? ?? 0).compareTo((b.value as Map)['ts'] as int? ?? 0));
        _cache.remove(oldest.first.key);
      }
      await _save();
      AppLog.add('clean ip: ${good.length}/${candidates.length} Cloudflare IPs answered '
          '(best ${good.isEmpty ? '-' : '${good.first[0]} ${good.first[1]} ms'}, normal $base ms, ipv6 $ipv6) on $key');
    } catch (e) {
      AppLog.add('clean ip: scan failed ($e)');
    } finally {
      _scanning = false;
    }
  }
}
