import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';
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

  @override
  Future<bool> healthCheck(EngineOptions options) async {
    final port = _proxyPort;
    return port != null && _core.process != null && await _core.verifyThroughProxy(port, options.testUrl);
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
    final port = options.localPort > 0 ? options.localPort : await SingboxCore.freePort();
    final api = await SingboxCore.freePort();
    final mtu = options.tunMode ? await NetworkInfo.tunMtu(options.tunMtu) : 1420;
    if (options.tunMode) AppLog.add('windows: tun mtu $mtu');
    final proc = await _core.start(_core.connectConfig(outbound, port, api, options,
        tun: options.tunMode, mtu: mtu, directProcesses: free ? WinFreeRoutes.processNames : const []));
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
      return false;
    }
    if (!await _core.verifyThroughProxy(port, options.testUrl)) {
      AppLog.add('windows: no traffic through ${server.displayName}');
      await disconnect();
      return false;
    }
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
    await _releaseProxy();
    await _core.stop();
    await _free.stop();
  }
}
