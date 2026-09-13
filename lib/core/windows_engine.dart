import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';
import 'engine.dart';
import 'server.dart';
import 'singbox_outbound.dart';
import 'win_system_proxy.dart';

const _proxyOwnedKey = 'win_proxy_owned';

/// Windows: bundled sing-box.exe (1.12) — local proxy + system proxy, or full TUN VPN as administrator.
class WindowsEngine implements VpnEngine {
  final _states = StreamController<VpnState>.broadcast();
  final _traffic = StreamController<TrafficStat>.broadcast();
  final _outbounds = <String, Json?>{};
  late Directory _work;
  Process? _proc;
  HttpClient? _trafficClient;
  int? _proxyPort;

  String get _bin => '${File(Platform.resolvedExecutable).parent.path}\\sing-box.exe';

  static bool get isAdmin {
    try {
      final isUserAnAdmin = DynamicLibrary.open('shell32.dll').lookupFunction<Int32 Function(), int Function()>('IsUserAnAdmin');
      return isUserAnAdmin() != 0;
    } catch (_) {
      return false;
    }
  }

  /// Starts a UAC-elevated copy of the app; the caller exits afterwards.
  static Future<void> relaunchAsAdmin() => Process.start(
        'powershell',
        ['-NoProfile', '-WindowStyle', 'Hidden', '-Command', "Start-Process -FilePath '${Platform.resolvedExecutable.replaceAll("'", "''")}' -Verb RunAs"],
        mode: ProcessStartMode.detached,
      );

  @override
  Stream<VpnState> get states => _states.stream;

  @override
  Stream<TrafficStat> get traffic => _traffic.stream;

  @override
  String? get httpProxy => _proxyPort == null ? null : '127.0.0.1:$_proxyPort';

  Json? _outbound(Server s) => _outbounds.putIfAbsent(s.uri, () => parseOutbound(s.uri));

  @override
  bool supports(Server server) => _outbound(server) != null;

  @override
  Future<void> init() async {
    final base = await getApplicationSupportDirectory();
    _work = Directory('${base.path}\\core')..createSync(recursive: true);
    await _releaseProxy(); // a previous run may have been killed while connected
    if (!File(_bin).existsSync()) throw StateError('sing-box.exe کنار برنامه پیدا نشد');
  }

  static Future<int> _freePort() async {
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
      File('${_work.path}\\$name.json').writeAsString(jsonEncode(config));

  // detachedWithStdio: no console window pops up for the child process.
  Future<Process> _spawn(List<String> args) =>
      Process.start(_bin, args, workingDirectory: _work.path, mode: ProcessStartMode.detachedWithStdio);

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

  Future<bool> _waitApi(int api) async {
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

  static Json _tagged(Json outbound, String tag, EngineOptions o) {
    final result = {...outbound, 'tag': tag};
    final tls = outbound['tls'];
    if (o.fragment && tls is Map && tls['enabled'] == true && tls['reality'] == null) {
      result['tls'] = {...tls, 'record_fragment': true};
    }
    return result;
  }

  @override
  Future<List<int>> pingAll(List<Server> servers, EngineOptions options,
      {void Function(int done)? onProgress, bool Function()? isCancelled, void Function(int index, int delay)? onResult}) async {
    final results = List<int>.filled(servers.length, -1);
    final outbounds = [
      for (var i = 0; i < servers.length; i++) _tagged(_outbound(servers[i]) ?? const {}, 'p$i', options),
    ];
    final usable = [for (var i = 0; i < servers.length; i++) if (_outbound(servers[i]) != null) i];
    final valid = await _validSubset(usable, outbounds);
    final skipped = servers.length - valid.length;
    AppLog.add('windows: ping ${servers.length} servers, ${valid.length} valid configs');
    onProgress?.call(skipped);
    if (valid.isEmpty) return results;

    final api = await _freePort();
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
      if (!await _waitApi(api)) {
        AppLog.add('windows: ping core API did not start');
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

  Future<bool> _verifyThroughProxy(int port, String testUrl) async {
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

  Json _connectConfig(Json outbound, int port, int api, EngineOptions o) {
    final base = _baseConfig('warn');
    return {
      ...base,
      'dns': {
        'servers': [
          {'type': 'local', 'tag': 'local'},
          if (o.tunMode) {'type': 'https', 'tag': 'remote', 'server': '1.1.1.1', 'detour': 'proxy'},
        ],
        'final': o.tunMode ? 'remote' : 'local',
        'strategy': 'prefer_ipv4',
      },
      'inbounds': [
        {'type': 'mixed', 'tag': 'in', 'listen': '127.0.0.1', 'listen_port': port},
        if (o.tunMode)
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
        _tagged(outbound, 'proxy', o),
        {'type': 'direct', 'tag': 'direct'},
        if (o.warp case final warp?) warp.singBoxOutbound('warp', 'proxy'),
      ],
      'route': {
        'rules': [
          {'action': 'sniff'},
          if (o.tunMode) {'protocol': 'dns', 'action': 'hijack-dns'},
          {'ip_is_private': true, 'outbound': 'direct'},
          if (o.bypassIran) {'domain_suffix': ['ir'], 'outbound': 'direct'},
        ],
        'final': o.warp != null ? 'warp' : 'proxy',
        'auto_detect_interface': true,
        'default_domain_resolver': 'local',
      },
      'experimental': {'clash_api': {'external_controller': '127.0.0.1:$api'}},
    };
  }

  @override
  Future<bool> connect(Server server, EngineOptions options) async {
    if (options.tunMode && !isAdmin) throw const AdminRequiredError();
    await disconnect();
    final outbound = _outbound(server);
    if (outbound == null) return false;
    final port = options.localPort > 0 ? options.localPort : await _freePort();
    final api = await _freePort();
    final file = await _writeConfig('active', _connectConfig(outbound, port, api, options));
    final proc = await _spawn(['run', '-c', file.path]);
    _proc = proc;
    _logStderr(proc, 'core');
    // stdout closes when the process exits: handle a crash while connected.
    unawaited(proc.stdout.drain<void>().whenComplete(() async {
      if (!identical(_proc, proc)) return;
      _proc = null;
      _proxyPort = null;
      if (options.killSwitch && !options.tunMode && options.systemProxy) {
        // Kill switch: point browsers at a dead proxy so nothing leaks until reconnect or disconnect.
        WinSystemProxy.enable('127.0.0.1:9');
      } else {
        await _releaseProxy();
      }
      _states.add(VpnState.disconnected);
    }));

    if (!await _waitApi(api)) {
      AppLog.add('windows: core did not start for ${server.displayName} (see sing-box lines above)');
      await disconnect();
      return false;
    }
    if (!await _verifyThroughProxy(port, options.testUrl)) {
      AppLog.add('windows: no traffic through ${server.displayName}');
      await disconnect();
      return false;
    }
    _proxyPort = port;
    if (options.systemProxy && !options.tunMode) {
      WinSystemProxy.enable('127.0.0.1:$port');
      await (await SharedPreferences.getInstance()).setBool(_proxyOwnedKey, true);
    }
    unawaited(_streamTraffic(api));
    return true;
  }

  static void _logStderr(Process proc, String label) {
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      final l = line.toLowerCase();
      if (l.contains('error') || l.contains('fatal') || l.contains('warn')) AppLog.add('sing-box[$label]: $line');
    }, onError: (_) {});
  }

  Future<void> _streamTraffic(int api) async {
    final client = HttpClient();
    _trafficClient = client;
    try {
      final res = await (await client.getUrl(Uri.parse('http://127.0.0.1:$api/traffic'))).close();
      await for (final line in res.transform(utf8.decoder).transform(const LineSplitter())) {
        if (line.trim().isEmpty) continue;
        final m = jsonDecode(line) as Map;
        _traffic.add(TrafficStat(up: (m['up'] as num).toInt(), down: (m['down'] as num).toInt()));
      }
    } catch (_) {}
  }

  Future<void> _releaseProxy() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_proxyOwnedKey) ?? false) {
      WinSystemProxy.disable();
      await prefs.remove(_proxyOwnedKey);
    }
  }

  @override
  Future<void> disconnect() async {
    final proc = _proc;
    _proc = null;
    _proxyPort = null;
    _trafficClient?.close(force: true);
    _trafficClient = null;
    await _releaseProxy();
    if (proc != null) Process.killPid(proc.pid);
  }
}
