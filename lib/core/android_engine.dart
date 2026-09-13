import 'dart:async';
import 'dart:convert';

import 'package:flutter_v2ray/flutter_v2ray.dart';

import 'engine.dart';
import 'server.dart';

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
          p.inbound['sniffing'] = {
            'enabled': true,
            'destOverride': ['http', 'tls'],
          };
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

  @override
  bool supports(Server server) => _supported.contains(server.protocol) && _config(server, const EngineOptions()) != null;

  @override
  Future<void> init() => _v2.initializeV2Ray();

  @override
  Future<List<int>> pingAll(List<Server> servers, EngineOptions options,
      {void Function(int done)? onProgress, bool Function()? isCancelled}) {
    final pingOptions = options.forPing;
    return runPool(servers.length, 8, (i) async {
      final config = _config(servers[i], pingOptions);
      if (config == null || (isCancelled?.call() ?? false)) return -1;
      final delay = await _v2
          .getServerDelay(config: config, url: options.testUrl)
          .timeout(options.timeout + const Duration(seconds: 2), onTimeout: () => -1);
      return delay > 0 && delay < options.timeout.inMilliseconds ? delay : -1;
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
    if (!options.proxyOnly && !await _v2.requestPermission()) throw const PermissionDeniedError();
    if (_coreState != 'DISCONNECTED') {
      await _v2.stopV2Ray();
      await _waitFor('DISCONNECTED', const Duration(seconds: 3));
    }
    await _v2.startV2Ray(
      remark: server.displayName,
      config: config,
      blockedApps: options.excludedApps.isEmpty ? null : options.excludedApps,
      proxyOnly: options.proxyOnly,
      notificationDisconnectButtonName: 'قطع اتصال',
    );
    if (await _waitFor('CONNECTED', const Duration(seconds: 12))) {
      for (var attempt = 0; attempt < 2; attempt++) {
        final delay = await _v2
            .getConnectedServerDelay(url: options.testUrl)
            .timeout(const Duration(seconds: 12), onTimeout: () => -1);
        if (delay > 0) return true;
      }
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
