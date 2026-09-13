import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_log.dart';
import 'engine.dart';
import 'server.dart';
import 'singbox_outbound.dart';

/// A sing-box (1.12) binary driven as a child process: config generation, validation, parallel delay tests
/// through the Clash API, and a local mixed (HTTP+SOCKS) proxy. Shared by the Windows and Android engines.
class SingboxCore {
  SingboxCore({required this.binary, required this.workDir, required this.label, this.detectInterface = true});

  final String binary;
  final Directory workDir;
  final String label;

  /// `auto_detect_interface` needs netlink access, which Android apps do not have.
  final bool detectInterface;

  final _outbounds = <String, Json?>{};
  Process? process;
  HttpClient? _trafficClient;

  bool get binaryExists => File(binary).existsSync();

  // WARP routes depend on the (later registered) identity, so they are not cached.
  Json? outbound(Server s) =>
      s.uri.startsWith('warp://') ? parseOutbound(s.uri) : _outbounds.putIfAbsent(s.uri, () => parseOutbound(s.uri));

  static Future<int> freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  /// Local DNS resolves proxy server domains (required by sing-box 1.12 when servers use domains).
  static Json _baseConfig(String logLevel) => {
        'log': {'level': logLevel},
        'dns': {
          'servers': [
            {'type': 'local', 'tag': 'local'},
          ],
        },
      };

  Future<File> _writeConfig(String name, Json config) =>
      File('${workDir.path}${Platform.pathSeparator}$name.json').writeAsString(jsonEncode(config));

  // detachedWithStdio: no console window pops up on Windows.
  Future<Process> _spawn(List<String> args) =>
      Process.start(binary, args, workingDirectory: workDir.path, mode: ProcessStartMode.detachedWithStdio);

  void _logStderr(Process proc, String what) {
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      final l = line.toLowerCase();
      if (l.contains('error') || l.contains('fatal') || l.contains('warn')) AppLog.add('sing-box[$label/$what]: $line');
    }, onError: (_) {});
  }

  static Json tagged(Json outbound, String tag, EngineOptions o) {
    final result = {...outbound, 'tag': tag};
    final tls = outbound['tls'];
    if (o.fragment && tls is Map && tls['enabled'] == true && tls['reality'] == null) {
      result['tls'] = {...tls, 'record_fragment': true};
    }
    return result;
  }

  Future<bool> _configValid(List<Json> outbounds) async {
    final file = await _writeConfig('check', {
      ..._baseConfig('error'),
      'outbounds': outbounds,
      'route': {'default_domain_resolver': 'local'},
    });
    final p = await _spawn(['check', '-c', file.path]);
    final output = await Future.wait([p.stdout.transform(utf8.decoder).join(), p.stderr.transform(utf8.decoder).join()]);
    final text = output.join().toLowerCase();
    return !text.contains('fatal') && !text.contains('error');
  }

  /// One bad outbound makes sing-box reject the whole config, so bisect to drop only the bad ones.
  Future<List<int>> _validSubset(List<int> indices, List<Json> outbounds) async {
    if (indices.isEmpty || await _configValid([for (final i in indices) outbounds[i]])) return indices;
    if (indices.length == 1) return const [];
    final mid = indices.length ~/ 2;
    return [
      ...await _validSubset(indices.sublist(0, mid), outbounds),
      ...await _validSubset(indices.sublist(mid), outbounds),
    ];
  }

  Future<bool> waitApi(int api) async {
    final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 500);
    try {
      for (var i = 0; i < 60; i++) {
        try {
          final res = await (await client.getUrl(Uri.parse('http://127.0.0.1:$api/version'))).close();
          await res.drain<void>();
          if (res.statusCode == 200) return true;
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<int> _delay(HttpClient client, int api, String tag, EngineOptions o) async {
    try {
      final uri = Uri.parse('http://127.0.0.1:$api/proxies/$tag/delay')
          .replace(queryParameters: {'timeout': '${o.timeout.inMilliseconds}', 'url': o.testUrl});
      final res = await (await client.getUrl(uri)).close().timeout(o.timeout + const Duration(seconds: 3));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return -1;
      final delay = (jsonDecode(body) as Map)['delay'];
      return delay is int && delay > 0 ? delay : -1;
    } catch (_) {
      return -1;
    }
  }

  /// Tests many servers at once in one throwaway sing-box process.
  Future<List<int>> pingAll(List<Server> servers, EngineOptions options,
      {void Function(int done)? onProgress, bool Function()? isCancelled, void Function(int index, int delay)? onResult}) async {
    final results = List<int>.filled(servers.length, -1);
    final outbounds = [
      for (var i = 0; i < servers.length; i++) tagged(outbound(servers[i]) ?? const {}, 'p$i', options),
    ];
    final usable = [for (var i = 0; i < servers.length; i++) if (outbound(servers[i]) != null) i];
    final valid = await _validSubset(usable, outbounds);
    final skipped = servers.length - valid.length;
    AppLog.add('$label: ping ${servers.length} servers, ${valid.length} valid configs');
    onProgress?.call(skipped);
    if (valid.isEmpty) return results;

    final api = await freePort();
    final file = await _writeConfig('ping', {
      ..._baseConfig('error'),
      'outbounds': [for (final i in valid) outbounds[i], {'type': 'direct', 'tag': 'direct'}],
      'route': {'default_domain_resolver': 'local'},
      'experimental': {'clash_api': {'external_controller': '127.0.0.1:$api'}},
    });
    final proc = await _spawn(['run', '-c', file.path]);
    unawaited(proc.stdout.drain<void>());
    _logStderr(proc, 'ping');
    final client = HttpClient();
    try {
      if (!await waitApi(api)) {
        AppLog.add('$label: ping core API did not start');
        return results;
      }
      final delays = await runPool(valid.length, 16, (k) async {
        if (isCancelled?.call() ?? false) return -1;
        final delay = await _delay(client, api, 'p${valid[k]}', options);
        onResult?.call(valid[k], delay);
        return delay;
      }, onProgress: (n) => onProgress?.call(skipped + n));
      for (var k = 0; k < valid.length; k++) {
        results[valid[k]] = delays[k];
      }
      return results;
    } finally {
      client.close(force: true);
      Process.killPid(proc.pid);
    }
  }

  /// Config for a live connection: local mixed proxy on [port], optional TUN (Windows), optional WARP chain.
  Json connectConfig(Json outbound, int port, int api, EngineOptions o, {bool tun = false}) => {
        ..._baseConfig('warn'),
        'dns': {
          'servers': [
            {'type': 'local', 'tag': 'local'},
            if (tun) {'type': 'https', 'tag': 'remote', 'server': '1.1.1.1', 'detour': 'proxy'},
          ],
          'final': tun ? 'remote' : 'local',
          'strategy': 'prefer_ipv4',
        },
        'inbounds': [
          {'type': 'mixed', 'tag': 'in', 'listen': '127.0.0.1', 'listen_port': port},
          if (tun)
            {
              'type': 'tun',
              'tag': 'tun',
              'interface_name': 'MobinVPN',
              'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
              'auto_route': true,
              'strict_route': o.killSwitch,
              'stack': 'mixed',
            },
        ],
        'outbounds': [
          tagged(outbound, 'proxy', o),
          {'type': 'direct', 'tag': 'direct'},
          if (o.warp case final warp?) warp.singBoxOutbound('warp', 'proxy'),
        ],
        'route': {
          'rules': [
            {'action': 'sniff'},
            if (tun) {'protocol': 'dns', 'action': 'hijack-dns'},
            {'ip_is_private': true, 'outbound': 'direct'},
            if (o.bypassIran) {'domain_suffix': ['ir'], 'outbound': 'direct'},
          ],
          'final': o.warp != null ? 'warp' : 'proxy',
          if (detectInterface) 'auto_detect_interface': true,
          'default_domain_resolver': 'local',
        },
        'experimental': {'clash_api': {'external_controller': '127.0.0.1:$api'}},
      };

  Future<Process> start(Json config) async {
    await stop();
    final file = await _writeConfig('active', config);
    final proc = await _spawn(['run', '-c', file.path]);
    process = proc;
    _logStderr(proc, 'core');
    return proc;
  }

  Future<bool> verifyThroughProxy(int port, String testUrl) async {
    final client = HttpClient()
      ..findProxy = ((_) => 'PROXY 127.0.0.1:$port')
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final res = await (await client.getUrl(Uri.parse(testUrl))).close().timeout(const Duration(seconds: 10));
          await res.drain<void>();
          if (res.statusCode >= 200 && res.statusCode < 400) return true;
        } catch (_) {}
      }
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> streamTraffic(int api, StreamController<TrafficStat> sink) async {
    final client = HttpClient();
    _trafficClient = client;
    try {
      final res = await (await client.getUrl(Uri.parse('http://127.0.0.1:$api/traffic'))).close();
      await for (final line in res.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        final m = jsonDecode(line) as Map;
        sink.add(TrafficStat(up: (m['up'] as num).toInt(), down: (m['down'] as num).toInt()));
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    final proc = process;
    process = null;
    _trafficClient?.close(force: true);
    _trafficClient = null;
    if (proc != null) Process.killPid(proc.pid);
  }
}
