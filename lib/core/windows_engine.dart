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
import 'singbox_outbound.dart';
import 'warp.dart';
import 'win_free_routes.dart';
import 'win_system_proxy.dart';

const _proxyOwnedKey = 'win_proxy_owned';

/// Windows: bundled sing-box.exe — local proxy + Windows system proxy, or full TUN VPN as administrator.
class WindowsEngine implements VpnEngine {
  final _states = StreamController<VpnState>.broadcast();
  final _traffic = StreamController<TrafficStat>.broadcast();
  late SingboxCore _core;
  late WinFreeRoutes _free;

  /// Second sing-box process: local SOCKS → WARP, upstream of "Psiphon + WARP".
  late SingboxCore _warpHelper;

  /// WARP endpoint of the last working WARP connection ("host:port"); chains and multi-path dial it.
  String _warpEndpoint = WarpAccount.endpoints.first;

  static const _chainWarpTag = 'chain-warp';
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
  bool supports(Server server) =>
      server.uri.startsWith('warp://') ||
      FreeRoutes.isFree(server) ||
      WinFreeRoutes.isChain(server) ||
      _core.outbound(server) != null;

  /// Starts the WARP helper proxy and returns its port once traffic passes, else null.
  Future<int?> _startWarpHelper(EngineOptions options) async {
    final warp = parseOutbound('warp://$_warpEndpoint');
    if (warp == null) return null;
    onPhase?.call('راه‌اندازی WARP برای Psiphon…');
    final port = await SingboxCore.freePort();
    final api = await SingboxCore.freePort();
    await _warpHelper.start(_warpHelper.warpSocksConfig(warp, port, api));
    if (await _warpHelper.waitApi(api) &&
        await _warpHelper.verifyThroughProxy(port, options.testUrl, attempts: 1)) {
      return port;
    }
    AppLog.add('windows: WARP helper for Psiphon did not pass traffic ($_warpEndpoint)');
    await _warpHelper.stop();
    return null;
  }

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

  bool _multiPath = false, _plainRetry = false;
  Map<String, String> _memberNames = const {};

  /// Multi-path: display name of the group member sing-box currently uses, or null (off / unknown).
  Future<String?> activeMember() async {
    final api = _api;
    if (!_multiPath || api == null || _core.process == null) return null;
    final tag = await _core.currentMember(api);
    return tag == null ? null : (_memberNames[tag] ?? tag);
  }

  /// Moves the running core to the next backup server; returns it, or null when none is left.
  /// Multi-path groups pick their member themselves (a urltest cannot be switched through the API).
  Future<Server?> failover() async {
    final api = _api;
    if (_multiPath || api == null || _core.process == null || _activeIndex >= _activeStandby.length) return null;
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
    _warpHelper = SingboxCore(
      binary: '${File(Platform.resolvedExecutable).parent.path}\\sing-box.exe',
      workDir: Directory('${base.path}\\core\\warp-helper')..createSync(recursive: true),
      label: 'warp-helper',
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
    final chain = WinFreeRoutes.isChain(server);
    Map<String, dynamic>? outbound;
    var extraOutbounds = const <Map<String, dynamic>>[];
    if (free) {
      // Smart chain: "Psiphon + WARP" first starts a local WARP proxy as Psiphon's upstream.
      String? upstream;
      if (server.uri == WinFreeRoutes.psiphonOverWarp.uri) {
        final helper = await _startWarpHelper(options);
        if (helper == null) return false;
        upstream = 'socks5://127.0.0.1:$helper';
      }
      // Psiphon / Tor run locally; sing-box just forwards to their SOCKS port.
      final socks = await _free.start(FreeRoutes.routeOf(server),
          isCancelled: isCancelled, onPhase: onPhase, upstreamProxy: upstream);
      if (socks == null) {
        await _free.stop();
        await _warpHelper.stop();
        return false;
      }
      outbound = {'type': 'socks', 'server': '127.0.0.1', 'server_port': socks, 'version': '5'};
      onPhase?.call('راه‌اندازی تونل ${server.displayName}…');
    } else if (chain) {
      // Smart chain: the V2Ray server is dialed inside WARP (its IP is never contacted from this network).
      final inner = _core.outbound(WinFreeRoutes.innerOf(server));
      final warp = parseOutbound('warp://$_warpEndpoint');
      if (inner == null || warp == null) return false;
      outbound = {...inner, 'detour': _chainWarpTag};
      extraOutbounds = [
        {...warp, 'tag': _chainWarpTag},
      ];
    } else {
      outbound = _core.outbound(server);
    }
    if (outbound == null) return false;
    // Anti-DPI retry: after failures, rotate the uTLS fingerprint and (ws) add early data.
    final failures = free ? 0 : (_failures[server.uri] ?? 0);
    if (failures > 0) outbound = evasive(outbound, failures);
    // Cloudflare CDN server: dial a clean edge IP found on this network (SNI/Host unchanged).
    final original = outbound;
    if (!chain) outbound = CleanIp.apply(outbound);
    final cleanIp = identical(outbound, original) ? null : outbound['server'] as String?;
    if (cleanIp != null) AppLog.add('windows: ${server.displayName} via clean Cloudflare IP $cleanIp');
    final port = options.localPort > 0 ? options.localPort : await SingboxCore.freePort();
    final api = await SingboxCore.freePort();
    final mtu = options.tunMode ? await NetworkInfo.tunMtu(options.tunMtu) : 1420;
    if (options.tunMode) AppLog.add('windows: tun mtu $mtu');
    final backups = <Server>[];
    final backupOutbounds = <Map<String, dynamic>>[];
    if (!free && !chain) {
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
    // Multi-path: a direct WARP endpoint joins the urltest group when the identity exists.
    final multiPath = options.multiPath && !free && !chain;
    final warpMember =
        multiPath && !_plainRetry && WarpRegistry.account != null ? parseOutbound('warp://$_warpEndpoint') : null;
    _multiPath = multiPath;
    _memberNames = {
      'proxy-0': server.displayName,
      for (final (i, b) in backups.indexed) 'proxy-${i + 1}': b.displayName,
      SingboxCore.multiPathWarpTag: 'WARP',
    };
    final proc = await _core.start(_core.connectConfig(outbound, port, api, multiPath == options.multiPath ? options : options.withoutMultiPath,
        tun: options.tunMode,
        mtu: mtu,
        directProcesses: free ? WinFreeRoutes.processNames : const [],
        standby: backupOutbounds,
        warpMember: warpMember,
        extraOutbounds: extraOutbounds));
    // stdout closes when the process exits: handle a crash while connected.
    unawaited(proc.stdout.drain<void>().whenComplete(() async {
      if (!identical(_core.process, proc)) return;
      _core.process = null;
      _proxyPort = null;
      await _free.stop();
      await _warpHelper.stop();
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
      if (backups.isNotEmpty || warpMember != null) {
        // A backup (or WARP member) config may be what the core rejected: try once more with the main server alone.
        final saved = standby;
        standby = const [];
        _plainRetry = true;
        try {
          return await connect(server, options);
        } finally {
          standby = saved;
          _plainRetry = false;
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
    if (server.uri.startsWith('warp://')) _warpEndpoint = server.uri.substring('warp://'.length);
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
    _multiPath = false;
    await _releaseProxy();
    await _core.stop();
    await _free.stop();
    await _warpHelper.stop();
  }
}
