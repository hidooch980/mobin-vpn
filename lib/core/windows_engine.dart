import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine.dart';
import 'server.dart';
import 'singbox_outbound.dart';
import 'win_system_proxy.dart';

const _testUrl = 'https://www.gstatic.com/generate_204';
const _proxyOwnedKey = 'win_proxy_owned';

/// Windows: bundled sing-box.exe as a local proxy + Windows system proxy.
class WindowsEngine implements VpnEngine {
  final _states = StreamController<VpnState>.broadcast();
  final _traffic = StreamController<TrafficStat>.broadcast();
  final _outbounds = <String, Json?>{};
  late Directory _work;
  Process? _proc;
  HttpClient? _trafficClient;

  String get _bin => '${File(Platform.resolvedExecutable).parent.path}\\sing-box.exe';

  @override
  Stream<VpnState> get states => _states.stream;

  @override
  Stream<TrafficStat> get traffic => _traffic.stream;

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

  Future<File> _writeConfig(String name, Json config) =>
      File('${_work.path}\\$name.json').writeAsString(jsonEncode(config));

  // detachedWithStdio: no console window pops up for the child process.
  Future<Process> _spawn(List<String> args) =>
      Process.start(_bin, args, workingDirectory: _work.path, mode: ProcessStartMode.detachedWithStdio);

  Future<bool> _configValid(List<Json> outbounds) async {
    final file = await _writeConfig('check', {'log': {'level': 'error'}, 'outbounds': outbounds});
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
      for (var i = 0; i < 40; i++) {
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

  Future<int> _delay(HttpClient client, int api, String tag) async {
    try {
      final uri = Uri.parse('http://127.0.0.1:$api/proxies/$tag/delay')
          .replace(queryParameters: {'timeout': '6000', 'url': _testUrl});
      final res = await (await client.getUrl(uri)).close().timeout(const Duration(seconds: 9));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) return -1;
      final delay = (jsonDecode(body) as Map)['delay'];
      return delay is int && delay > 0 ? delay : -1;
    } catch (_) {
      return -1;
    }
  }

  @override
  Future<List<int>> pingAll(List<Server> servers, {void Function(int done)? onProgress, bool Function()? isCancelled}) async {
    final results = List<int>.filled(servers.length, -1);
    final outbounds = [
      for (var i = 0; i < servers.length; i++) <String, dynamic>{...?_outbound(servers[i]), 'tag': 'p$i'},
    ];
    final usable = [for (var i = 0; i < servers.length; i++) if (_outbound(servers[i]) != null) i];
    final valid = await _validSubset(usable, outbounds);
    final skipped = servers.length - valid.length;
    onProgress?.call(skipped);
    if (valid.isEmpty) return results;

    final api = await _freePort();
    final file = await _writeConfig('ping', {
      'log': {'level': 'error'},
      'outbounds': [for (final i in valid) outbounds[i], {'type': 'direct', 'tag': 'direct'}],
      'experimental': {'clash_api': {'external_controller': '127.0.0.1:$api'}},
    });
    final proc = await _spawn(['run', '-c', file.path]);
    unawaited(proc.stdout.drain<void>());
    unawaited(proc.stderr.drain<void>());
    final client = HttpClient();
    try {
      if (!await _waitApi(api)) return results;
      final delays = await runPool(valid.length, 16, (k) async {
        if (isCancelled?.call() ?? false) return -1;
        return _delay(client, api, 'p${valid[k]}');
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

  Future<bool> _verifyThroughProxy(int port) async {
    final client = HttpClient()
      ..findProxy = ((_) => 'PROXY 127.0.0.1:$port')
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final res = await (await client.getUrl(Uri.parse(_testUrl))).close().timeout(const Duration(seconds: 10));
          await res.drain<void>();
          if (res.statusCode == 204 || res.statusCode == 200) return true;
        } catch (_) {}
      }
      return false;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<bool> connect(Server server) async {
    await disconnect();
    final outbound = _outbound(server);
    if (outbound == null) return false;
    final port = await _freePort(), api = await _freePort();
    final file = await _writeConfig('active', {
      'log': {'level': 'warn'},
      'inbounds': [
        {'type': 'mixed', 'tag': 'in', 'listen': '127.0.0.1', 'listen_port': port},
      ],
      'outbounds': [
        {...outbound, 'tag': 'proxy'},
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {
        'rules': [
          {'ip_is_private': true, 'outbound': 'direct'},
        ],
        'final': 'proxy',
        'auto_detect_interface': true,
      },
      'experimental': {'clash_api': {'external_controller': '127.0.0.1:$api'}},
    });
    final proc = await _spawn(['run', '-c', file.path]);
    _proc = proc;
    unawaited(proc.stderr.drain<void>());
    // stdout closes when the process exits: handle a crash while connected.
    unawaited(proc.stdout.drain<void>().whenComplete(() async {
      if (identical(_proc, proc)) {
        _proc = null;
        await _releaseProxy();
        _states.add(VpnState.disconnected);
      }
    }));

    if (!await _waitApi(api) || !await _verifyThroughProxy(port)) {
      await disconnect();
      return false;
    }
    WinSystemProxy.enable('127.0.0.1:$port');
    await (await SharedPreferences.getInstance()).setBool(_proxyOwnedKey, true);
    unawaited(_streamTraffic(api));
    return true;
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
    _trafficClient?.close(force: true);
    _trafficClient = null;
    await _releaseProxy();
    if (proc != null) Process.killPid(proc.pid);
  }
}
