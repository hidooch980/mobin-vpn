import 'dart:async';
import 'dart:io';

/// Download / upload speed through the local proxy (the tunnel) using speed.cloudflare.com.
class SpeedTest {
  SpeedTest._();

  static const _downBytes = 10 * 1000 * 1000, _upBytes = 2 * 1000 * 1000;
  static const _limit = Duration(seconds: 20);

  /// Mbps (download, upload); a direction that failed is null.
  static Future<({double? down, double? up})> run(String proxy) async {
    final client = HttpClient()
      ..findProxy = ((_) => 'PROXY $proxy')
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final down = await _download(client);
      final up = await _upload(client);
      return (down: down, up: up);
    } finally {
      client.close(force: true);
    }
  }

  static double _mbps(int bytes, Duration elapsed) =>
      elapsed.inMicroseconds <= 0 ? 0 : bytes * 8 / 1e6 / (elapsed.inMicroseconds / 1e6);

  static Future<double?> _download(HttpClient client) async {
    try {
      final watch = Stopwatch()..start();
      final req = await client.getUrl(Uri.parse('https://speed.cloudflare.com/__down?bytes=$_downBytes'));
      final res = await req.close().timeout(_limit);
      if (res.statusCode != 200) return null;
      var received = 0;
      // Stops at the time limit and measures what arrived so far.
      await for (final chunk in res.timeout(_limit)) {
        received += chunk.length;
        if (watch.elapsed > _limit) break;
      }
      return received == 0 ? null : _mbps(received, watch.elapsed);
    } catch (_) {
      return null;
    }
  }

  static Future<double?> _upload(HttpClient client) async {
    try {
      final watch = Stopwatch()..start();
      final req = await client.postUrl(Uri.parse('https://speed.cloudflare.com/__up'));
      req.headers.contentType = ContentType.binary;
      req.contentLength = _upBytes;
      const chunk = 64 * 1000;
      final block = List<int>.filled(chunk, 0);
      for (var sent = 0; sent < _upBytes; sent += chunk) {
        req.add(sent + chunk <= _upBytes ? block : block.sublist(0, _upBytes - sent));
      }
      final res = await req.close().timeout(_limit);
      await res.drain<void>().timeout(_limit);
      if (res.statusCode >= 400) return null;
      return _mbps(_upBytes, watch.elapsed);
    } catch (_) {
      return null;
    }
  }
}
