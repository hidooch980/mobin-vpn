import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'app_log.dart';
import 'network_info.dart';

/// Opt-in anonymous server quality reports and the shared server scores.
/// Only a server fingerprint, success/failure, latency and network type are ever sent.
class ServerReports {
  static const _base = 'https://molido-sub.hidooch980.workers.dev';
  static const warpNode = 'mode:warp';

  static final Map<String, String> _fpCache = {};
  static String? _version;

  /// First 16 hex chars of SHA-256 over the server URI without its "#remark", trimmed.
  static Future<String> fingerprint(String uri) async {
    final cached = _fpCache[uri];
    if (cached != null) return cached;
    final hash = uri.indexOf('#');
    final clean = (hash < 0 ? uri : uri.substring(0, hash)).trim();
    final digest = await Sha256().hash(utf8.encode(clean));
    final hex = digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return _fpCache[uri] = hex.substring(0, 16);
  }

  static Future<String> _netType() async {
    final key = await NetworkInfo.networkKey();
    if (key == 'wifi') return 'wifi';
    if (key.startsWith('mobile')) return 'cellular';
    return 'other';
  }

  static Future<String> _appVersion() async {
    try {
      return _version ??= (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return 'unknown';
    }
  }

  /// Fire-and-forget; never throws. [node] is a fingerprint or [warpNode].
  static Future<void> send({required String node, required bool ok, int? ms, String? proxy}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    if (proxy != null) client.findProxy = (_) => 'PROXY $proxy';
    try {
      final body = jsonEncode({
        'v': 1,
        'node': node,
        'ok': ok,
        'ms': ms,
        'net': await _netType(),
        'app': Platform.isWindows ? 'windows' : Platform.operatingSystem,
        'ver': await _appVersion(),
        if (NetworkInfo.operatorBucket case final op?) 'op': op,
      });
      final req = await client.postUrl(Uri.parse('$_base/report')).timeout(const Duration(seconds: 10));
      req.headers.contentType = ContentType.json;
      req.write(body);
      final res = await req.close().timeout(const Duration(seconds: 10));
      await res.drain<void>().timeout(const Duration(seconds: 10));
    } catch (e) {
      AppLog.add('report: not sent ($e)');
    } finally {
      client.close(force: true);
    }
  }

  /// Fingerprint -> score (0..1), or null when the endpoint is unreachable.
  /// [op]: ISP bucket (see [NetworkInfo.operatorBucket]) so scores reflect the user's operator.
  static Future<Map<String, double>?> fetchScores({String? proxy, String? op}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    if (proxy != null) client.findProxy = (_) => 'PROXY $proxy';
    try {
      final url = op == null ? '$_base/scores' : '$_base/scores?op=${Uri.encodeQueryComponent(op)}';
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 10));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 10)));
      if (json is! Map) return null;
      final out = <String, double>{};
      for (final e in json.entries) {
        final v = e.value;
        final score = v is Map ? v['score'] : null;
        if (score is num) out['${e.key}'] = score.toDouble();
      }
      return out;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
