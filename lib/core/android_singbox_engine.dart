import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'android_engine.dart';
import 'app_log.dart';
import 'engine.dart';
import 'server.dart';
import 'singbox_core.dart';

/// Android with the sing-box core: sing-box (bundled as libsingbox.so) connects to the server — all protocols,
/// parallel delay tests — and the Xray VpnService only carries device traffic into sing-box's local SOCKS port.
/// The app's own package is excluded from the tunnel so sing-box's server connections do not loop back into it.
class AndroidSingboxEngine implements VpnEngine {
  AndroidSingboxEngine(this._tunnel);

  final AndroidEngine _tunnel;
  final _states = StreamController<VpnState>.broadcast();
  final _traffic = StreamController<TrafficStat>.broadcast();
  static const _channel = MethodChannel('mobin/native');
  SingboxCore? _core;
  String _package = '';

  bool get available => _core?.binaryExists ?? false;

  @override
  Stream<VpnState> get states => _states.stream;

  @override
  Stream<TrafficStat> get traffic => _traffic.stream;

  @override
  String? get httpProxy => null;

  @override
  bool supports(Server server) => available && _core!.outbound(server) != null;

  @override
  Future<bool> requestPermission() => _tunnel.requestPermission();

  // The tunnel's own delay test goes device → Xray → sing-box → server, so it covers the whole chain.
  @override
  Future<bool> healthCheck(EngineOptions options) async =>
      (_core?.process != null) && await _tunnel.healthCheck(options);

  @override
  Future<void> init() async {
    final libDir = await _channel.invokeMethod<String>('nativeLibDir');
    final base = await getApplicationSupportDirectory();
    _core = SingboxCore(
      binary: '$libDir/libsingbox.so',
      workDir: Directory('${base.path}/core')..createSync(recursive: true),
      label: 'android',
      detectInterface: false,
    );
    _package = (await PackageInfo.fromPlatform()).packageName;
    AppLog.add('android sing-box core ${available ? 'ready' : 'missing'} ($libDir)');
  }

  @override
  Future<List<int>> pingAll(List<Server> servers, EngineOptions options,
      {void Function(int done)? onProgress, bool Function()? isCancelled, void Function(int index, int delay)? onResult}) async {
    if (!available) return List<int>.filled(servers.length, -1);
    return _core!.pingAll(servers, options.forPing, onProgress: onProgress, isCancelled: isCancelled, onResult: onResult);
  }

  static const _privateRanges = ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '127.0.0.0/8', '169.254.0.0/16'];

  /// Xray config for the VpnService: everything goes to sing-box's local SOCKS inbound.
  static String _tunnelConfig(int port, EngineOptions o) => jsonEncode({
        'log': {'loglevel': 'warning'},
        'inbounds': [
          {
            'tag': 'in_proxy',
            'port': 10808,
            'protocol': 'socks',
            'listen': '127.0.0.1',
            'settings': {'auth': 'noauth', 'udp': true, 'userLevel': 8},
            'sniffing': {
              'enabled': true,
              'destOverride': ['http', 'tls'],
            },
          },
        ],
        'outbounds': [
          {
            'tag': 'proxy',
            'protocol': 'socks',
            'settings': {
              'servers': [
                {'address': '127.0.0.1', 'port': port},
              ],
            },
          },
          {'tag': 'direct', 'protocol': 'freedom', 'settings': <String, dynamic>{}},
        ],
        'dns': {
          'servers': [o.dns],
        },
        'routing': {
          'domainStrategy': 'AsIs',
          'rules': [
            {'type': 'field', 'ip': _privateRanges, 'outboundTag': 'direct'},
            if (o.bypassIran) {'type': 'field', 'domain': ['domain:ir'], 'outboundTag': 'direct'},
          ],
        },
      });

  @override
  Future<bool> connect(Server server, EngineOptions options) async {
    final core = _core;
    if (core == null || !available) throw StateError('هسته‌ی sing-box در این نسخه موجود نیست');
    await disconnect();
    final outbound = core.outbound(server);
    if (outbound == null) return false;
    final port = await SingboxCore.freePort(), api = await SingboxCore.freePort();
    final proc = await core.start(core.connectConfig(outbound, port, api, options));
    unawaited(proc.stdout.drain<void>().whenComplete(() async {
      if (!identical(core.process, proc)) return;
      core.process = null;
      AppLog.add('android: sing-box exited while connected');
      await _tunnel.disconnect();
      _states.add(VpnState.disconnected);
    }));

    if (!await core.waitApi(api)) {
      AppLog.add('android: sing-box did not start for ${server.displayName}');
      await core.stop();
      return false;
    }
    if (!await core.verifyThroughProxy(port, options.testUrl)) {
      AppLog.add('android: no traffic through ${server.displayName} (sing-box)');
      await core.stop();
      return false;
    }
    final ok = await _tunnel.startTunnel(
      remark: server.displayName,
      config: _tunnelConfig(port, options),
      options: options,
      extraBlockedApps: [_package],
    );
    if (!ok) {
      await core.stop();
      return false;
    }
    unawaited(core.streamTraffic(api, _traffic));
    return true;
  }

  @override
  Future<void> disconnect() async {
    await _tunnel.disconnect();
    await _core?.stop();
  }
}

/// Picks the Android core per the user's setting (Xray or sing-box) and forwards everything to it.
class AndroidHybridEngine implements VpnEngine {
  AndroidHybridEngine(this._coreSetting) {
    _xray.states.listen(_states.add);
    _singbox.states.listen(_states.add);
    _xray.traffic.listen((t) {
      if (!_usingSingbox) _traffic.add(t);
    });
    _singbox.traffic.listen(_traffic.add);
  }

  final String Function() _coreSetting;
  final _xray = AndroidEngine();
  late final _singbox = AndroidSingboxEngine(_xray);
  final _states = StreamController<VpnState>.broadcast();
  final _traffic = StreamController<TrafficStat>.broadcast();
  VpnEngine? _connected;

  bool get _auto => _coreSetting() == 'auto';
  bool get _usingSingbox => (_auto ? _preferred != _xray : _coreSetting() == 'singbox') && _singbox.available;
  VpnEngine get _active => _usingSingbox ? _singbox : _xray;

  /// Auto mode: the core that last connected is tried first next time.
  VpnEngine? _preferred;

  @override
  Stream<VpnState> get states => _states.stream;

  @override
  Stream<TrafficStat> get traffic => _traffic.stream;

  @override
  String? get httpProxy => null;

  @override
  bool supports(Server server) => _auto ? _singbox.supports(server) || _xray.supports(server) : _active.supports(server);

  @override
  Future<void> init() async {
    await _xray.init();
    try {
      await _singbox.init();
    } catch (e) {
      AppLog.add('android sing-box init failed: $e');
    }
  }

  @override
  Future<bool> requestPermission() => _xray.requestPermission();

  @override
  Future<bool> healthCheck(EngineOptions options) async => await _connected?.healthCheck(options) ?? false;

  @override
  Future<List<int>> pingAll(List<Server> servers, EngineOptions options,
          {void Function(int done)? onProgress, bool Function()? isCancelled, void Function(int index, int delay)? onResult}) =>
      _active.pingAll(servers, options, onProgress: onProgress, isCancelled: isCancelled, onResult: onResult);

  @override
  Future<bool> connect(Server server, EngineOptions options) async {
    final order = <VpnEngine>[_active];
    if (_auto) {
      final other = identical(_active, _singbox) ? _xray : _singbox;
      if (other.supports(server)) order.add(other);
    }
    for (final core in order) {
      if (!core.supports(server)) continue;
      final previous = _connected;
      if (previous != null) await previous.disconnect();
      _connected = null;
      if (await core.connect(server, options)) {
        _connected = core;
        if (_auto) _preferred = core;
        return true;
      }
      if (order.length > 1) AppLog.add('auto core: ${identical(core, _singbox) ? 'sing-box' : 'Xray'} failed, trying the other core');
    }
    return false;
  }

  @override
  Future<void> disconnect() async {
    await (_connected ?? _active).disconnect();
    _connected = null;
  }
}
