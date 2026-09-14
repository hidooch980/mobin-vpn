import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';
import 'cf_clean_ip.dart';
import 'engine.dart';
import 'free_routes.dart';
import 'network_info.dart';
import 'server.dart';
import 'singbox_core.dart';
import 'win_free_routes.dart';
import 'win_system_proxy.dart';

const _proxyOwnedKey = 'win_proxy_owned';

/// Windows: bundled sing-box.exe — local proxy + Windows system proxy, or full TUN VPN as administrator.
class WindowsEngine implements VpnEngine {
  final _states = StreamController<VpnState>.broadcast();
  final _traffic = StreamController<TrafficStat>.broadcast();
  late SingboxCore _core;
  late WinFreeRoutes _free;
  int? _proxyPort;

  /// Status line while Psiphon / Tor is starting (set by the controller).
  void Function(String phase)? onPhase;

  /// Set by the controller so a slow Psiphon/Tor start can be cancelled.
  bool Function() isCancelled = () => false;

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

  @override
  bool supports(Server server) => server.uri.startsWith('warp://') || FreeRoutes.isFree(server) || _core.outbound(server) != null;

  @override
  Future<bool> requestPermission() async => true;

  /// Pre-tested backup servers for the next [connect] (set by the controller); switched to by [failover].
  List<Server> standby = const [];
  List<Server> _activeStandby = const [];
  int _activeIndex = 0;
  int? _api;

  /// Quick check (one request, 4 s) so a frozen tunnel is noticed within a few seconds.
  @override
  Future<bool> healthCheck(EngineOptions options) async {
    final port = _proxyPort;
    return port != null &&
        _core.process != null &&
        await _core.verifyThroughProxy(port, options.testUrl, attempts: 1, timeout: const Duration(seconds: 4));
  }

  /// Moves the running core to the next backup server; returns it, or null when none is left.
  Future<Server?> failover() async {
    final api = _api;
    if (api == null || _core.process == null || _activeIndex >= _activeStandby.length) return null;
    final next = _activeIndex + 1;
    if (!await _core.selectOutbound(api, 'proxy-$next')) return null;
    _activeIndex = next;
    final server = _activeStandby[next - 1];
    AppLog.add('windows: failover to backup ${server.displayName}');
    return server;
  }

  @override
  Future<void> init() async {
    final base = await getApplicationSupportDirectory();
    _core = SingboxCore(
      binary: '${File(Platform.resolvedExecutable).parent.path}\\sing-box.exe',
      workDir: Directory('${base.path}\\core')..createSync(recursive: true),
      label: 'windows',
    );
    _free = WinFreeRoutes(
      appDir: File(Platform.resolvedExecutable).parent.path,
      dataDir: Directory('${base.path}\\free')..createSync(recursive: true),
    );
    await _free.cleanupStale();
    unawaited(_core.updateIranRuleSets());
    await _releaseProxy(); // a previous run may have been killed while connected
    if (!_core.binaryExists) throw StateError('sing-box.exe کنار برنامه پیدا نشد');
  }

  @override
  Future<List<int>> pingAll(List<Server> servers, EngineOptions options,
          {void Function(int done)? onProgress, bool Function()? isCancelled, void Function(int index, int delay)? onResult}) =>
      _core.pingAll(servers, options.forPing, onProgress: onProgress, isCancelled: isCancelled, onResult: onResult);

  /// Failed real connections per server uri (this session), for [evasive] retries.
  final _failures = <String, int>{};

  static const _fingerprints = ['firefox', 'safari', 'randomized'];

  /// Copy of a TCP-TLS outbound (vless/vmess/trojan) with the uTLS fingerprint rotated by [failures]
  /// (firefox → safari → randomized) and, from the second failure, WebSocket early data when not set.
  static Map<String, dynamic> evasive(Map<String, dynamic> outbound, int failures) {
    if (failures <= 0 || !const {'vless', 'vmess', 'trojan'}.contains(outbound['type'])) return outbound;
    final result = {...outbound};
    final tls = outbound['tls'];
    if (tls is Map && tls['enabled'] == true) {
      result['tls'] = {
        ...Map<String, dynamic>.from(tls),
        'utls': {'enabled': true, 'fingerprint': _fingerprints[(failures - 1) % _fingerprints.length]},
      };
    }
    final transport = outbound['transport'];
    if (failures >= 2 && transport is Map && transport['type'] == 'ws' && transport['max_early_data'] == null) {
      result['transport'] = {
        ...Map<String, dynamic>.from(transport),
        'max_early_data': 2048,
        'early_data_header_name': 'Sec-WebSocket-Protocol',
      };
    }
    return result;
  }

  /// Background re-ping while idle: few parallel tests so the PC and UI stay responsive.
  Future<List<int>> prewarm(List<Server> servers, EngineOptions options, {bool Function()? isCancelled}) =>
      _core.pingAll(servers, options.forPing, isCancelled: isCancelled, concurrency: 4);

  @override
  Future<bool> connect(Server server, EngineOptions options) async {
    if (options.tunMode && !isAdmin) throw const AdminRequiredError();
    await disconnect();
    final free = FreeRoutes.isFree(server);
    Map<String, dynamic>? outbound;
    if (free) {
      // Psiphon / Tor run locally; sing-box just forwards to their SOCKS port.
      final socks = await _free.start(FreeRoutes.routeOf(server), isCancelled: isCancelled, onPhase: onPhase);
      if (socks == null) {
        await _free.stop();
        return false;
      }
      outbound = {'type': 'socks', 'server': '127.0.0.1', 'server_port': socks, 'version': '5'};
      onPhase?.call('راه‌اندازی تونل ${server.displayName}…');
    } else {
      outbound = _core.outbound(server);
    }
    if (outbound == null) return false;
    // Anti-DPI retry: after failures, rotate the uTLS fingerprint and (ws) add early data.
    final failures = free ? 0 : (_failures[server.uri] ?? 0);
    if (failures > 0) outbound = evasive(outbound, failures);
    // Cloudflare CDN server: dial a clean edge IP found on this network (SNI/Host unchanged).
    final original = outbound;
    outbound = CleanIp.apply(outbound);
    final cleanIp = identical(outbound, original) ? null : outbound['server'] as String?;
    if (cleanIp != null) AppLog.add('windows: ${server.displayName} via clean Cloudflare IP $cleanIp');
    final port = options.localPort > 0 ? options.localPort : await SingboxCore.freePort();
    final api = await SingboxCore.freePort();
    final mtu = options.tunMode ? await NetworkInfo.tunMtu(options.tunMtu) : 1420;
    if (options.tunMode) AppLog.add('windows: tun mtu $mtu');
    final backups = <Server>[];
    final backupOutbounds = <Map<String, dynamic>>[];
    if (!free) {
      for (final s in standby) {
        if (s.uri == server.uri || FreeRoutes.isFree(s) || s.uri.startsWith('warp://')) continue;
        final o = _core.outbound(s);
        if (o == null) continue;
        backups.add(s);
        backupOutbounds.add(CleanIp.apply(o));
      }
    }
    _activeStandby = backups;
    _activeIndex = 0;
    final proc = await _core.start(_core.connectConfig(outbound, port, api, options,
        tun: options.tunMode,
        mtu: mtu,
        directProcesses: free ? WinFreeRoutes.processNames : const [],
        standby: backupOutbounds));
    // stdout closes when the process exits: handle a crash while connected.
    unawaited(proc.stdout.drain<void>().whenComplete(() async {
      if (!identical(_core.process, proc)) return;
      _core.process = null;
      _proxyPort = null;
      await _free.stop();
      if (options.killSwitch && !options.tunMode && options.systemProxy) {
        // Kill switch: point browsers at a dead proxy so nothing leaks until reconnect or disconnect.
        WinSystemProxy.enable('127.0.0.1:9');
      } else {
        await _releaseProxy();
      }
      _states.add(VpnState.disconnected);
    }));

    if (!await _core.waitApi(api)) {
      AppLog.add('windows: core did not start for ${server.displayName} (see sing-box lines above)');
      await disconnect();
      if (backups.isNotEmpty) {
        // A backup config may be what the core rejected: try once more with the main server alone.
        final saved = standby;
        standby = const [];
        try {
          return await connect(server, options);
        } finally {
          standby = saved;
        }
      }
      return false;
    }
    _api = api;
    if (!await _core.verifyThroughProxy(port, options.testUrl)) {
      AppLog.add('windows: no traffic through ${server.displayName}');
      await disconnect();
      if (cleanIp != null) CleanIp.markBad(cleanIp);
      if (!free) _failures[server.uri] = failures + 1;
      return false;
    }
    _failures.remove(server.uri);
    _proxyPort = port;
    // Fetch or refresh the Iranian rule-sets for the next connection (daily, through the tunnel if needed).
    if (options.bypassIran && options.iranRuleSets) unawaited(_core.updateIranRuleSets(proxy: '127.0.0.1:$port'));
    if (options.systemProxy && !options.tunMode) {
      WinSystemProxy.enable('127.0.0.1:$port');
      await (await SharedPreferences.getInstance()).setBool(_proxyOwnedKey, true);
    }
    unawaited(_core.streamTraffic(api, _traffic));
    return true;
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
    _proxyPort = null;
    _api = null;
    _activeStandby = const [];
    _activeIndex = 0;
    await _releaseProxy();
    await _core.stop();
    await _free.stop();
  }
}
