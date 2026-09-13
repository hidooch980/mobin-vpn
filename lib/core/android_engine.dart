import 'dart:async';

import 'package:flutter_v2ray/flutter_v2ray.dart';

import 'engine.dart';
import 'server.dart';

const _testUrl = 'https://www.gstatic.com/generate_204';

/// Android: Xray core through VpnService (flutter_v2ray).
class AndroidEngine implements VpnEngine {
  final _states = StreamController<VpnState>.broadcast();
  final _traffic = StreamController<TrafficStat>.broadcast();
  final _configs = <String, String?>{};
  late final FlutterV2ray _v2 = FlutterV2ray(onStatusChanged: _onStatus);
  String _coreState = 'DISCONNECTED';

  static const _supported = {Protocol.vless, Protocol.vmess, Protocol.trojan, Protocol.shadowsocks};

  @override
  Stream<VpnState> get states => _states.stream;

  @override
  Stream<TrafficStat> get traffic => _traffic.stream;

  void _onStatus(V2RayStatus status) {
    _coreState = status.state;
    _traffic.add(TrafficStat(up: status.uploadSpeed, down: status.downloadSpeed));
    if (status.state == 'DISCONNECTED') _states.add(VpnState.disconnected);
  }

  String? _config(Server s) => _configs.putIfAbsent(s.uri, () {
        try {
          return FlutterV2ray.parseFromURL(s.uri).getFullConfiguration();
        } catch (_) {
          return null;
        }
      });

  @override
  bool supports(Server server) => _supported.contains(server.protocol) && _config(server) != null;

  @override
  Future<void> init() => _v2.initializeV2Ray();

  @override
  Future<List<int>> pingAll(List<Server> servers, {void Function(int done)? onProgress, bool Function()? isCancelled}) {
    return runPool(servers.length, 8, (i) async {
      final config = _config(servers[i]);
      if (config == null || (isCancelled?.call() ?? false)) return -1;
      final delay = await _v2
          .getServerDelay(config: config, url: _testUrl)
          .timeout(const Duration(seconds: 10), onTimeout: () => -1);
      return delay > 0 ? delay : -1;
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
  Future<bool> connect(Server server) async {
    final config = _config(server);
    if (config == null) return false;
    if (!await _v2.requestPermission()) throw const PermissionDeniedError();
    if (_coreState != 'DISCONNECTED') {
      await _v2.stopV2Ray();
      await _waitFor('DISCONNECTED', const Duration(seconds: 3));
    }
    await _v2.startV2Ray(
      remark: server.displayName,
      config: config,
      proxyOnly: false,
      notificationDisconnectButtonName: 'قطع اتصال',
    );
    if (await _waitFor('CONNECTED', const Duration(seconds: 12))) {
      for (var attempt = 0; attempt < 2; attempt++) {
        final delay = await _v2
            .getConnectedServerDelay(url: _testUrl)
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
