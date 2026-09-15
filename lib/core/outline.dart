import 'dart:convert';
import 'dart:io';

/// Outline dynamic access keys: `ssconf://host/path#name` is fetched as `https://host/path`; the answer is JSON
/// `{server, server_port, password, method}` or a plain `ss://` line. Resolved to a SIP002 `ss://` link.
class OutlineKeys {
  OutlineKeys._();

  static bool isDynamic(String link) => link.trim().toLowerCase().startsWith('ssconf://');

  /// SIP002 link from a key server response, or null when it is not usable. [name] becomes the remark.
  static String? ssFromResponse(String body, {String name = ''}) {
    final text = body.trim();
    final fragment = name.isEmpty ? '' : '#${Uri.encodeComponent(name)}';
    if (text.startsWith('ss://')) {
      final line = const LineSplitter().convert(text).first.trim();
      return line.contains('#') || fragment.isEmpty ? line : '$line$fragment';
    }
    try {
      final m = jsonDecode(text);
      if (m is! Map) return null;
      final server = '${m['server'] ?? ''}'.trim();
      final port = int.tryParse('${m['server_port'] ?? ''}');
      final password = '${m['password'] ?? ''}';
      final method = '${m['method'] ?? ''}'.trim();
      if (server.isEmpty || port == null || port <= 0 || port > 65535 || password.isEmpty || method.isEmpty) return null;
      final user = base64Url.encode(utf8.encode('$method:$password')).replaceAll('=', '');
      final host = server.contains(':') && !server.startsWith('[') ? '[$server]' : server;
      return 'ss://$user@$host:$port$fragment';
    } catch (_) {
      return null;
    }
  }

  /// Fetches [link] over HTTPS (through [proxy] "host:port" when given); null on any failure.
  static Future<String?> resolve(String link, {String? proxy}) async {
    final trimmed = link.trim();
    final hash = trimmed.indexOf('#');
    final name = hash < 0 ? 'Outline' : Uri.decodeComponent(trimmed.substring(hash + 1));
    final url = Uri.tryParse('https://${(hash < 0 ? trimmed : trimmed.substring(0, hash)).substring('ssconf://'.length)}');
    if (url == null || url.host.isEmpty) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    if (proxy != null) client.findProxy = (_) => 'PROXY $proxy';
    try {
      final res = await (await client.getUrl(url)).close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
      return res.statusCode == 200 ? ssFromResponse(body, name: name) : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
