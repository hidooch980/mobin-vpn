import 'dart:async';
import 'dart:convert';

import 'package:flutter_v2ray/flutter_v2ray.dart';

import 'app_log.dart';
import 'engine.dart';
import 'server.dart';
import 'singbox_outbound.dart';

/// Android: Xray core through VpnService (flutter_v2ray).
class AndroidEngine implements VpnEngine {
  final _states = StreamController<VpnState>.broadcast();
  final _traffic = StreamController<TrafficStat>.broadcast();
  final _configs = <String, String?>{};
  late final FlutterV2ray _v2 = FlutterV2ray(onStatusChanged: _onStatus);
  String _coreState = 'DISCONNECTED';

  static const _supported = {Protocol.vless, Protocol.vmess, Protocol.trojan, Protocol.shadowsocks};
  static const _privateRanges = ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '127.0.0.0/8', '169.254.0.0/16'];

  @override
  Stream<VpnState> get states => _states.stream;

  @override
  Stream<TrafficStat> get traffic => _traffic.stream;

  // The VpnService already routes this app's own traffic.
  @override
  String? get httpProxy => null;

  void _onStatus(V2RayStatus status) {
    _coreState = status.state;
    _traffic.add(TrafficStat(up: status.uploadSpeed, down: status.downloadSpeed));
    if (status.state == 'DISCONNECTED') _states.add(VpnState.disconnected);
  }

  String? _config(Server s, EngineOptions o) => _configs.putIfAbsent('${o.configKey}|${s.uri}', () {
        try {
          final p = FlutterV2ray.parseFromURL(s.uri);
          p.dns = {
            'servers': [o.dns],
          };
          // Same as v2rayNG: sniff only for routing decisions (don't rewrite destinations) and
          // route by domain as-is instead of resolving every domain first (UseIp was slow).
          p.inbound['sniffing'] = {
            'enabled': true,
            'destOverride': ['http', 'tls'],
            'routeOnly': true,
          };
          p.routing['domainStrategy'] = 'AsIs';
          p.routing['rules'] = [
            {'type': 'field', 'ip': _privateRanges, 'outboundTag': 'direct'},
            if (o.bypassIran) {'type': 'field', 'domain': ['domain:ir'], 'outboundTag': 'direct'},
          ];
          final config = p.getFullConfiguration();
          return o.fragment || o.warp != null ? _postProcess(config, o) : config;
        } catch (_) {
          return null;
        }
      });

  /// Fragment: splits the TLS ClientHello (Xray freedom "fragment") to slip past SNI filtering.
  /// WARP: a WireGuard outbound dialed through the server becomes the default route.
  static String _postProcess(String config, EngineOptions o) {
    final json = jsonDecode(config) as Map<String, dynamic>;
    final outbounds = json['outbounds'] as List;
    final proxy = outbounds.first as Map<String, dynamic>;
    final proxyTag = proxy['tag'] as String? ?? 'proxy';
    proxy['tag'] = proxyTag;
    final stream = (proxy['streamSettings'] as Map<String, dynamic>?) ?? {};
    if (o.fragment && stream['security'] == 'tls') {
      stream['sockopt'] = {...?(stream['sockopt'] as Map<String, dynamic>?), 'dialerProxy': 'fragment'};
      proxy['streamSettings'] = stream;
      outbounds.add({
        'tag': 'fragment',
        'protocol': 'freedom',
        'settings': {
          'fragment': {'packets': 'tlshello', 'length': '10-20', 'interval': '10-20'},
        },
      });
    }
    final warp = o.warp;
    if (warp != null) {
      outbounds.add(warp.xrayOutbound('warp', proxyTag));
      final routing = json['routing'] as Map<String, dynamic>;
      routing['rules'] = [
        ...(routing['rules'] as List? ?? const []),
        {'type': 'field', 'network': 'tcp,udp', 'outboundTag': 'warp'},
      ];
    }
    return jsonEncode(json);
  }

  // Lightweight validity check: building a full Xray config for hundreds of servers on the UI thread froze the app.
  // The real config is built lazily, only for servers that are pinged or connected.
  final _valid = <String, bool>{};

  @override
  bool supports(Server server) =>
      _supported.contains(server.protocol) && _valid.putIfAbsent(server.uri, () => parseOutbound(server.uri) != null);

  @override
  Future<void> init() => _v2.initializeV2Ray();

  @override
  Future<bool> requestPermission() => _v2.requestPermission();

  @override
  Future<bool> healthCheck(EngineOptions options) async {
    if (_coreState != 'CONNECTED') return false;
    final delay = await _v2
        .getConnectedServerDelay(url: options.testUrl)
        .timeout(const Duration(seconds: 10), onTimeout: () => -1);
    return delay > 0;
  }

  /// The plugin measures delays on a single native thread, so requests must go one at a time:
  /// firing several at once made queued requests hit the Dart timeout and every server looked dead.
  @override
  Future<List<int>> pingAll(List<Server> servers, EngineOptions options,
      {void Function(int done)? onProgress, bool Function()? isCancelled, void Function(int index, int delay)? onResult}) {
    final pingOptions = options.forPing;
    return runPool(servers.length, 1, (i) async {
      final config = _config(servers[i], pingOptions);
      if (config == null || (isCancelled?.call() ?? false)) return -1;
      final raw = await _v2
          .getServerDelay(config: config, url: options.testUrl)
          .timeout(options.timeout + const Duration(seconds: 4), onTimeout: () => -1);
      final delay = raw > 0 ? raw : -1;
      onResult?.call(i, delay);
      return delay;
    }, onProgress: onProgress);
  }

  Future<bool> _waitFor(String state, Duration limit) async {
    final end = DateTime.now().add(limit);
    while (DateTime.now().isBefore(end)) {
      if (_coreState == state) return true;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return _coreState == state;
  }

  @override
  Future<bool> connect(Server server, EngineOptions options) async {
    final config = _config(server, options);
    if (config == null) return false;
    return startTunnel(remark: server.displayName, config: config, options: options);
  }

  /// Starts the VpnService with any Xray [config] and returns true once traffic passes through it.
  /// Also used by the sing-box engine, whose Xray config just forwards to sing-box's local port.
  Future<bool> startTunnel({
    required String remark,
    required String config,
    required EngineOptions options,
    List<String> extraBlockedApps = const [],
  }) async {
    if (!options.proxyOnly && !await _v2.requestPermission()) throw const PermissionDeniedError();
    if (_coreState != 'DISCONNECTED') {
      await _v2.stopV2Ray();
      await _waitFor('DISCONNECTED', const Duration(seconds: 3));
    }
    final blocked = [...options.excludedApps, ...extraBlockedApps];
    await _v2.startV2Ray(
      remark: remark,
      config: config,
      blockedApps: blocked.isEmpty ? null : blocked,
      proxyOnly: options.proxyOnly,
      notificationDisconnectButtonName: 'قطع اتصال',
    );
    if (!await _waitFor('CONNECTED', const Duration(seconds: 8))) {
      AppLog.add('android: core did not report CONNECTED for $remark (state=$_coreState)');
      await _v2.stopV2Ray();
      return false;
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final delay = await _v2
          .getConnectedServerDelay(url: options.testUrl)
          .timeout(const Duration(seconds: 7), onTimeout: () => -1);
      if (delay > 0) return true;
      AppLog.add('android: tunnel check ${attempt + 1} failed for $remark');
    }
    await _v2.stopV2Ray();
    return false;
  }

  @override
  Future<void> disconnect() async {
    if (_coreState == 'DISCONNECTED') return;
    await _v2.stopV2Ray();
    await _waitFor('DISCONNECTED', const Duration(seconds: 3));
  }
}
