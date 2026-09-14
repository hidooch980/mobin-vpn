import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account.dart';
import 'android_engine.dart';
import 'app_log.dart';
import 'countries.dart';
import 'free_routes.dart';
import 'engine.dart';
import 'network_info.dart';
import 'reports.dart';
import 'server.dart';
import 'settings.dart';
import 'subscription.dart';
import 'update_notifier.dart';
import 'updater.dart';
import 'usage_stats.dart';
import 'warp.dart';
import 'windows_engine.dart';

class CountryGroup {
  CountryGroup(this.code);

  final String code;
  final List<Server> servers = [];

  String get name => countryName(code);
}

class _Cancelled implements Exception {}

class _UserError implements Exception {
  const _UserError(this.message);
  final String message;
}

class VpnController extends ChangeNotifier {
  VpnController({VpnEngine? engine, SubscriptionRepository? repository})
      : _engineOverride = engine,
        repository = repository ?? SubscriptionRepository();

  final VpnEngine? _engineOverride;
  late final VpnEngine engine = _engineOverride ?? VpnEngine.create(settings);
  final SubscriptionRepository repository;
  final settings = AppSettings();
  final updater = Updater();
  final usage = UsageStats();
  final account = Account();

  // Traffic not yet reported to the account server (bytes).
  int _unreportedUp = 0, _unreportedDown = 0;

  static const _countryKey = 'country', _lastServerKey = 'last_server';
  static const _countryPoolSize = 30, _connectAttempts = 4;

  /// Completes once settings, cache and the first server refresh are done.
  final ready = Completer<void>();

  /// Pseudo location: starred servers only.
  static const favoritesMode = 'FAV';

  /// Country code given to user-imported configs (shown as "کانفیگ‌های من").
  static const manualCode = 'ZZ';

  /// Direct mode tries at most this many servers before giving up.
  static const _directAttempts = 6;

  /// Smart mode stops pinging after this many responsive servers (Android pings one by one, so stop at the first).
  static int get _enoughGood => Platform.isAndroid ? 1 : 3;

  SubscriptionData? _data;
  List<Server> servers = const [];
  List<CountryGroup> countries = const [];

  /// Last measured delay per server uri (-1 = failed).
  final Map<String, int> delays = {};

  /// null = automatic (best server from any country).
  String? selectedCountry;
  VpnState state = VpnState.disconnected;
  String? phase;
  int progressDone = 0, progressTotal = 0;
  Server? current;
  int? currentDelay;
  DateTime? connectedAt;
  TrafficStat traffic = const TrafficStat();
  DateTime? updatedAt;
  bool loading = false, pinging = false;
  String? error;
  bool _cancel = false, _userStopping = false;

  UpdateInfo? update;

  /// null = not downloading.
  double? updateProgress;

  double? get progress => progressTotal == 0 ? null : progressDone / progressTotal;

  EngineOptions get _options => EngineOptions(
        testUrl: settings.testUrl,
        timeout: Duration(seconds: settings.timeoutSeconds),
        proxyOnly: settings.proxyOnly,
        systemProxy: settings.systemProxy,
        tunMode: settings.tunMode,
        killSwitch: settings.killSwitch,
        localPort: settings.localPort,
        bypassIran: settings.bypassIran,
        dns: settings.dns,
        fragment: settings.fragment,
        excludedApps: settings.excludedApps.toList(),
        warp: settings.warp ? WarpAccount.fromJsonString(settings.warpAccount) : null,
        tunnelDns: settings.tunnelDns,
        tunMtu: settings.tunMtu,
        iranRuleSets: settings.bypassIran && settings.iranRuleSets,
      );

  Future<void> init() async {
    await Future.wait([settings.load(), usage.load()]);
    settings.addListener(() {
      final data = _data;
      if (data != null) _apply(data);
    });
    engine.states.listen((s) {
      if (s != VpnState.disconnected || state != VpnState.connected || _userStopping) return;
      final dropped = current;
      _markDisconnected();
      if (settings.autoReconnect) unawaited(_switchAway(dropped, alreadyDisconnected: true));
    });
    // Watchdog: a tunnel can stay "up" while the server stops passing traffic.
    Timer.periodic(const Duration(seconds: 5), (_) => _watchdog());
    engine.traffic.listen((t) {
      if (state != VpnState.connected) return;
      usage.add(t);
      _unreportedUp += t.up;
      _unreportedDown += t.down;
      traffic = t;
      notifyListeners();
    });
    final prefs = await SharedPreferences.getInstance();
    selectedCountry = prefs.getString(_countryKey);
    // The removed gaming mode was stored as 'GAME': fall back to automatic.
    if (selectedCountry == 'GAME') {
      selectedCountry = null;
      await prefs.remove(_countryKey);
    }
    try {
      await engine.init();
      AppLog.add('engine ready (${Platform.operatingSystem} ${Platform.operatingSystemVersion})');
    } catch (e) {
      AppLog.add('engine init failed: $e');
      error = 'راه‌اندازی هسته ناموفق بود: $e';
    }
    final cached = await repository.loadCached();
    if (cached != null) _apply(cached);
    await refresh();
    // Launched at Windows startup the network may not be up yet: give the server list a few more tries.
    for (var i = 0; i < 3 && _data == null && settings.connectOnLaunch; i++) {
      await Future<void>.delayed(const Duration(seconds: 8));
      await refresh();
    }
    if (!ready.isCompleted) ready.complete();
    unawaited(_loadScores());
    // Auto-connect uses the normal connect path, so the selected location (favorites, country) is respected.
    if (settings.connectOnLaunch && servers.isNotEmpty && state == VpnState.disconnected) {
      AppLog.add('auto-connect on launch (mode=${selectedCountry ?? 'auto'})');
      unawaited(connect());
    }
    await checkUpdate();
    // Long-running sessions (e.g. Windows left open) still hear about new releases and get fresh servers.
    Timer.periodic(const Duration(hours: 6), (_) => checkUpdate());
    Timer.periodic(const Duration(minutes: 30), (_) => refresh());
    if (Account.configured) Timer.periodic(const Duration(minutes: 1), (_) => _reportUsage());
  }

  /// Shared quality score (0..1) per server uri from the optional /scores endpoint; empty when unavailable.
  final Map<String, double> _scoreByUri = {};

  /// Operator bucket the current scores were loaded for ('' = none).
  String? _scoresOp;

  Future<void> _loadScores() async {
    try {
      final op = NetworkInfo.operatorBucket;
      _scoresOp = op ?? '';
      final scores = await ServerReports.fetchScores(proxy: engine.httpProxy, op: op);
      if (scores == null || scores.isEmpty) return;
      _scoreByUri.clear();
      for (final s in servers) {
        final node = _isWarp(s) ? ServerReports.warpNode : await ServerReports.fingerprint(s.uri);
        final score = scores[node];
        if (score != null) _scoreByUri[s.uri] = score;
      }
      AppLog.add('scores: ${_scoreByUri.length} servers scored');
    } catch (_) {
      // Optional: never affects connecting.
    }
  }

  /// Opt-in anonymous report of one connection attempt; fire-and-forget.
  void _report(Server server, bool ok, {int? ms}) {
    if (!settings.anonymousReports) return;
    unawaited(() async {
      try {
        final node = _isWarp(server) ? ServerReports.warpNode : await ServerReports.fingerprint(server.uri);
        var delay = ms != null && ms > 0 ? ms : null;
        if (ok && delay == null) delay = await measureConnection();
        await ServerReports.send(node: node, ok: ok, ms: delay, proxy: ok ? engine.httpProxy : null);
      } catch (_) {}
    }());
  }

  int _healthFailures = 0;
  bool _watching = false;

  /// Servers that recently dropped, skipped until the time stored here.
  final Map<String, DateTime> _badUntil = {};

  bool _isBad(Server s) => _badUntil[s.uri]?.isAfter(DateTime.now()) ?? false;

  /// Last working server is remembered per network (Wi-Fi, each SIM operator), like MSN-GUARD's per-SIM ladder.
  Future<String> _networkServerKey() async => '$_lastServerKey:${await NetworkInfo.networkKey()}';

  int _watchTick = 0;

  Future<void> _watchdog() async {
    _watchTick++;
    final fresh = connectedAt != null && DateTime.now().difference(connectedAt!) < const Duration(seconds: 40);
    if (!fresh && _watchTick % 3 != 0) return; // every 5 s while fresh, then every 15 s
    if (_watching || state != VpnState.connected || !settings.autoReconnect) {
      if (state != VpnState.connected) _healthFailures = 0;
      return;
    }
    _watching = true;
    try {
      final ok = await engine.healthCheck(_options);
      if (state != VpnState.connected) return;
      _healthFailures = ok ? 0 : _healthFailures + 1;
      if (!ok) AppLog.add('watchdog: no traffic through ${current?.displayName} ($_healthFailures)');
      // Right after connecting, two failed checks (~10 s) are enough to move on; later three (~45 s).
      final fresh = connectedAt != null && DateTime.now().difference(connectedAt!) < const Duration(seconds: 40);
      if (_healthFailures >= (fresh ? 2 : 3)) await _switchAway(current);
    } finally {
      _watching = false;
    }
  }

  /// Auto mode: the connected server stopped working — put it aside for 10 minutes and connect to another one.
  Future<void> _switchAway(Server? dropped, {bool alreadyDisconnected = false}) async {
    _healthFailures = 0;
    if (dropped != null) {
      _badUntil[dropped.uri] = DateTime.now().add(const Duration(minutes: 10));
      AppLog.add('auto switch: leaving ${dropped.displayName}');
    }
    if (!alreadyDisconnected) await disconnect();
    error = 'سرور ${dropped?.displayName ?? ''} قطع شد؛ جابه‌جایی خودکار به سرور دیگر…';
    notifyListeners();
    await connect();
  }

  /// Sends traffic used since the last report; disconnects when the panel has turned the account off.
  Future<void> _reportUsage() async {
    if (_unreportedUp == 0 && _unreportedDown == 0 && state != VpnState.connected) return;
    final up = _unreportedUp, down = _unreportedDown;
    _unreportedUp = _unreportedDown = 0;
    final status = await account.reportUsage(up, down);
    if (status != AccountStatus.ok && state == VpnState.connected) {
      AppLog.add('account: $status reported by server, disconnecting');
      await disconnect();
    }
  }

  /// Pseudo country code of the free WARP route.
  static const warpCode = 'WARP';

  /// Free WARP route: one entry per Cloudflare endpoint (no server list needed).
  static List<Server> get warpServers => [
        for (final (i, endpoint) in WarpAccount.endpoints.indexed)
          Server(
            uri: 'warp://$endpoint',
            remark: 'Cloudflare WARP ${(i + 1).toString().padLeft(2, '0')} · WG',
            countryCode: warpCode,
            protocol: Protocol.wireguard,
          ),
      ];

  bool _isWarp(Server s) => s.countryCode == warpCode;

  /// Applies the route setting to a candidate pool.
  List<Server> _byTransport(List<Server> pool) => switch (settings.transport) {
        'warp' => warpServers,
        'psiphon' when transportAvailable('psiphon') => [FreeRoutes.psiphon],
        'tor' when transportAvailable('tor') => [FreeRoutes.tor],
        'v2ray' => pool.where((s) => !_isWarp(s)).toList(),
        // Automatic: V2Ray servers, then free WARP, then Psiphon (and Tor on Windows) as the last resort.
        _ => [
            ...pool.where((s) => !_isWarp(s)),
            ...warpServers.take(4),
            if (transportAvailable('psiphon')) FreeRoutes.psiphon,
            if (Platform.isWindows) FreeRoutes.tor,
          ],
      };

  /// Whether a route choice ('auto', 'v2ray', 'warp', 'psiphon', 'tor') works on this platform.
  /// The UI uses this instead of a hard-coded "coming soon" flag.
  static bool transportAvailable(String t) => switch (t) {
        'psiphon' || 'tor' => Platform.isAndroid || Platform.isWindows,
        _ => true,
      };

  void _apply(SubscriptionData data) {
    _data = data;
    WarpRegistry.account = WarpAccount.fromJsonString(settings.warpAccount);
    final manual = [
      for (final link in settings.manualConfigs)
        if (Server.fromUri(link) case final s?)
          Server(uri: s.uri, remark: s.remark, countryCode: manualCode, protocol: s.protocol),
    ].where(engine.supports);
    servers = [
      ...manual,
      ...data.servers.where((s) => settings.protocols.contains(s.protocol) && engine.supports(s)),
      ...warpServers,
    ];
    final groups = <String, CountryGroup>{};
    for (final s in servers) {
      groups.putIfAbsent(s.countryCode, () => CountryGroup(s.countryCode)).servers.add(s);
    }
    countries = groups.values.toList();
    if (selectedCountry != null &&
        selectedCountry != favoritesMode &&
        !groups.containsKey(selectedCountry)) {
      selectedCountry = null;
    }
    updatedAt = data.updatedAt;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      _apply(await repository.fetch(customUrl: settings.customSubscription));
      AppLog.add('servers: ${servers.length} usable in ${countries.length} locations');
    } catch (e) {
      AppLog.add('servers: refresh failed: $e');
      if (servers.isEmpty) error = 'دریافت لیست سرورها ناموفق بود. اینترنت را بررسی کنید.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Returns the available update (also stored in [update]), null when up to date or offline.
  Future<UpdateInfo?> checkUpdate() async {
    try {
      update = await updater.check(proxy: engine.httpProxy);
      final found = update;
      if (found != null) unawaited(UpdateNotifier.notifyIfNew(found));
      notifyListeners();
    } catch (_) {
      // Offline or GitHub blocked: try again later.
    }
    return update;
  }

  Future<void> installUpdate() async {
    final info = update;
    if (info == null || updateProgress != null) return;
    updateProgress = 0;
    notifyListeners();
    try {
      final file = await updater.download(info, proxy: engine.httpProxy, onProgress: (p) {
        updateProgress = p;
        notifyListeners();
      });
      if (Platform.isWindows) await disconnect();
      await updater.install(file);
      if (Platform.isWindows) exit(0);
    } catch (e) {
      AppLog.add('update: failed: $e');
      error = 'به‌روزرسانی داخل برنامه ناموفق بود؛ صفحه‌ی دانلود در مرورگر باز شد. '
          'اگر گیت‌هاب باز نمی‌شود، اول وصل شوید و دوباره امتحان کنید.';
      unawaited(Updater.openReleasesPage());
    } finally {
      updateProgress = null;
      notifyListeners();
    }
  }

  Future<void> selectCountry(String? code) async {
    if (code == selectedCountry) return;
    selectedCountry = code;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    code == null ? await prefs.remove(_countryKey) : await prefs.setString(_countryKey, code);
    if (state == VpnState.connected) {
      await disconnect();
      await connect();
    }
  }

  Future<void> toggle() async {
    switch (state) {
      case VpnState.connected:
        await disconnect();
      case VpnState.connecting:
        // Cancel at once: stop the core now and let the running attempt unwind in the background.
        _cancel = true;
        unawaited(engine.disconnect());
        _markDisconnected();
      case VpnState.disconnected:
        await connect();
      case VpnState.disconnecting:
        break;
    }
  }

  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _notifyTimer;

  /// Big ping rounds report progress per server: rebuild the UI at most every 250 ms.
  void _throttledNotify() {
    const gap = Duration(milliseconds: 250);
    final since = DateTime.now().difference(_lastNotify);
    if (since >= gap) {
      _notifyTimer?.cancel();
      _notifyTimer = null;
      _lastNotify = DateTime.now();
      notifyListeners();
    } else {
      _notifyTimer ??= Timer(gap - since, () {
        _notifyTimer = null;
        _lastNotify = DateTime.now();
        notifyListeners();
      });
    }
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  /// Measures delay for [list] (servers screen) without connecting.
  Future<void> pingServers(List<Server> list) async {
    if (pinging || list.isEmpty) return;
    pinging = true;
    notifyListeners();
    try {
      final result = await engine.pingAll(list, _options);
      for (var i = 0; i < list.length; i++) {
        delays[list[i].uri] = result[i];
      }
    } finally {
      pinging = false;
      notifyListeners();
    }
  }

  /// Server picked in the list (v2rayNG style: tap selects, the connect button connects to it).
  Server? chosen;

  void choose(Server? server) {
    chosen = server;
    notifyListeners();
  }

  /// While connected: time for a request through the tunnel in ms, or null when it fails.
  Future<int?> measureConnection() async {
    if (state != VpnState.connected) return null;
    final watch = Stopwatch()..start();
    final ok = await engine.healthCheck(_options);
    return ok ? watch.elapsedMilliseconds : null;
  }

  bool isFavorite(Server s) => settings.favorites.contains(s.uri);

  Future<void> toggleFavorite(Server s) => settings.update((x) {
        final next = {...x.favorites};
        next.contains(s.uri) ? next.remove(s.uri) : next.add(s.uri);
        x.favorites = next;
      });

  /// Adds share links (one per line, or a base64 subscription body). Returns how many were new and valid.
  Future<int> addManualConfigs(String text) async {
    final found = parseSubscription(text).where(engine.supports).map((s) => s.uri);
    final existing = settings.manualConfigs.toSet();
    final fresh = found.where(existing.add).toList();
    if (fresh.isNotEmpty) await settings.update((x) => x.manualConfigs = [...fresh, ...x.manualConfigs]);
    return fresh.length;
  }

  Future<void> removeManualConfig(String uri) =>
      settings.update((x) => x.manualConfigs = x.manualConfigs.where((u) => u != uri).toList());

  /// Creates the WARP identity once; tries direct first, then through the active local proxy.
  Future<bool> ensureWarp() async {
    if (WarpAccount.fromJsonString(settings.warpAccount) != null) return true;
    for (final proxy in {null, engine.httpProxy}) {
      try {
        final account = await WarpAccount.register(proxy: proxy);
        WarpRegistry.account = account;
        await settings.update((x) => x.warpAccount = jsonEncode(account.toJson()));
        return true;
      } catch (_) {}
    }
    return false;
  }

  /// Connects to one specific server chosen by the user.
  Future<void> connectTo(Server server) async {
    if (state == VpnState.connected) await disconnect();
    await connect(only: server);
  }

  void _checkCancel() {
    if (_cancel) throw _Cancelled();
  }

  /// Round-robin across countries so a pool compares many locations, not only the first one.
  static List<Server> _roundRobin(List<CountryGroup> groups, int size) {
    final pool = <Server>[];
    for (var round = 0; pool.length < size; round++) {
      var added = false;
      for (final g in groups) {
        if (round < g.servers.length && pool.length < size) {
          pool.add(g.servers[round]);
          added = true;
        }
      }
      if (!added) break;
    }
    return pool;
  }

  Future<List<Server>> _candidates() async {
    final List<Server> pool;
    final country = selectedCountry;
    final size = settings.poolSize;
    if (country == favoritesMode) {
      final favorites = servers.where((s) => settings.favorites.contains(s.uri)).toList();
      final healthy = favorites.where((s) => !_isBad(s)).toList();
      return healthy.isEmpty ? favorites : healthy;
    }
    if (country != null) {
      pool = servers.where((s) => s.countryCode == country).take(_countryPoolSize).toList();
    } else {
      pool = _roundRobin(countries, size);
    }
    final last = (await SharedPreferences.getInstance()).getString(await _networkServerKey());
    final lastServer = servers.where((s) => s.uri == last).firstOrNull;
    if (lastServer != null && (country == null || lastServer.countryCode == country)) {
      pool
        ..remove(lastServer)
        ..insert(0, lastServer);
    }
    // Skip servers that just dropped, unless nothing else is left.
    final healthy = pool.where((s) => !_isBad(s)).toList();
    return healthy.isEmpty ? pool : healthy;
  }

  Future<void>? _connectRun;

  Future<void> connect({Server? only}) async {
    final previous = _connectRun;
    if (previous != null) await previous; // a cancelled attempt may still be unwinding
    if (state != VpnState.disconnected) return;
    final run = _connect(only);
    _connectRun = run;
    try {
      await run;
    } finally {
      if (identical(_connectRun, run)) _connectRun = null;
    }
  }

  Future<void> _connect(Server? only) async {
    error = null;
    _cancel = false;
    // The ISP became known (or changed) since scores were loaded: refresh them for this operator.
    if (_scoresOp != null && (NetworkInfo.operatorBucket ?? '') != _scoresOp) unawaited(_loadScores());
    state = VpnState.connecting;
    phase = 'در حال آماده‌سازی…';
    progressDone = progressTotal = 0;
    notifyListeners();
    var options = _options;
    final eng = engine;
    if (eng is AndroidEngine) {
      eng.isCancelled = () => _cancel;
      eng.onPhase = (text) {
        phase = text;
        notifyListeners();
      };
    } else if (eng is WindowsEngine) {
      eng.isCancelled = () => _cancel;
      eng.onPhase = (text) {
        phase = text;
        notifyListeners();
      };
    }
    try {
      if (Account.configured && await account.refreshStatus() != AccountStatus.ok) {
        throw const _UserError('حساب شما اجازه‌ی اتصال ندارد (غیرفعال یا روی دستگاه دیگر).');
      }
      // Ask for the VPN permission before anything else, so the system dialog shows immediately.
      if (!options.proxyOnly) {
        phase = 'دریافت اجازه‌ی VPN…';
        notifyListeners();
        final granted = await engine.requestPermission();
        AppLog.add('vpn permission: ${granted ? 'granted' : 'denied'}');
        if (!granted) throw const PermissionDeniedError();
      }
      if (servers.isEmpty && only == null) await refresh();
      if (settings.warp && options.warp == null) {
        phase = 'ساخت هویت Cloudflare WARP…';
        notifyListeners();
        if (await ensureWarp()) {
          options = _options;
        } else {
          error = 'ثبت WARP ناموفق بود؛ این بار بدون WARP وصل می‌شویم.';
        }
      }
      final List<Server> pool = only != null ? [only] : _byTransport(await _candidates());
      if (pool.any(_isWarp) && WarpRegistry.account == null) {
        phase = 'ساخت هویت رایگان Cloudflare WARP…';
        notifyListeners();
        if (!await ensureWarp()) {
          AppLog.add('warp: registration failed');
          pool.removeWhere(_isWarp);
          if (pool.isEmpty) {
            throw const _UserError('ثبت WARP ناموفق بود؛ اینترنت را بررسی کنید یا مسیر دیگری انتخاب کنید.');
          }
        }
      }
      if (pool.isEmpty) throw const _UserError('سروری برای این موقعیت پیدا نشد.');

      // Fast path like v2rayNG: reconnect straight to the last working server, no ping round.
      final last = (await SharedPreferences.getInstance()).getString(await _networkServerKey());
      if (only == null && pool.isNotEmpty && pool.first.uri == last) {
        final server = pool.first;
        phase = 'اتصال سریع به ${server.displayName}';
        notifyListeners();
        AppLog.add('connect: fast path to last server ${server.displayName}');
        if (await engine.connect(server, options)) {
          _checkCancel();
          current = server;
          currentDelay = null;
          connectedAt = DateTime.now();
          state = VpnState.connected;
          phase = null;
          notifyListeners();
          _report(server, true);
          return;
        }
        if (!_cancel) _report(server, false);
        AppLog.add('connect: fast path failed, testing servers');
        pool.removeAt(0);
        _checkCancel();
      }
      if (only != null) {
        // A server the user picked: connect directly, the tunnel check itself proves it works.
        phase = 'اتصال به ${only.displayName}';
        notifyListeners();
        if (await engine.connect(only, options)) {
          _checkCancel();
          current = only;
          connectedAt = DateTime.now();
          state = VpnState.connected;
          phase = null;
          notifyListeners();
          _report(only, true);
          await (await SharedPreferences.getInstance()).setString(await _networkServerKey(), only.uri);
          return;
        }
        if (!_cancel) _report(only, false);
        throw const _UserError('این سرور وصل نشد. سرور دیگری را امتحان کنید.');
      }

      {
        // Direct first (like v2rayNG): no ping round, try servers in order until one really carries traffic.
        final tried = pool.take(_directAttempts).toList();
        for (final server in tried) {
          _checkCancel();
          phase = 'اتصال مستقیم به ${server.displayName}';
          notifyListeners();
          if (await engine.connect(server, options)) {
            _checkCancel();
            AppLog.add('connect: direct to ${server.displayName} (${server.protocolLabel})');
            current = server;
            currentDelay = null;
            connectedAt = DateTime.now();
            state = VpnState.connected;
            phase = null;
            notifyListeners();
            _report(server, true);
            await (await SharedPreferences.getInstance()).setString(await _networkServerKey(), server.uri);
            return;
          }
          if (!_cancel) _report(server, false);
          AppLog.add('connect: direct ${server.displayName} failed');
        }
        // None worked: test the remaining servers and connect to the fastest responsive one.
        AppLog.add('connect: direct attempts failed, testing the other servers');
        pool.removeWhere(tried.contains);
        if (pool.isEmpty) throw const _UserError('اتصال برقرار نشد. لیست سرورها را به‌روزرسانی کنید یا کشور دیگری انتخاب کنید.');
      }

      phase = 'سنجش سرورها با اینترنت شما';
      progressTotal = pool.length;
      notifyListeners();
      AppLog.add('connect: mode=${selectedCountry ?? 'auto'} pool=${pool.length} platform=${Platform.operatingSystem}');
      // Smart/country modes stop testing once a few good servers are found — much faster, especially on Android.
      final canStopEarly = only == null;
      var good = 0;
      final measured = await engine.pingAll(
        pool,
        options,
        isCancelled: () => _cancel || (canStopEarly && good >= _enoughGood),
        onResult: (_, delay) {
          if (delay > 0 && delay < 2500) good++;
        },
        onProgress: (done) {
          progressDone = done;
          _throttledNotify();
        },
      );
      _checkCancel();
      AppLog.add('ping: ${measured.where((d) => d > 0).length}/${pool.length} responded '
          '(best ${measured.where((d) => d > 0).fold<int?>(null, (a, d) => a == null || d < a ? d : a)} ms)');
      for (var i = 0; i < pool.length; i++) {
        delays[pool[i].uri] = measured[i];
      }

      // Fastest first; within the same ~100 ms band, the shared quality score (when available) breaks the tie.
      int band(int i) => measured[i] ~/ 100;
      double score(int i) => _scoreByUri[pool[i].uri] ?? -1;
      var ranked = [for (var i = 0; i < pool.length; i++) if (measured[i] > 0) i]
        ..sort((a, b) {
          final byBand = band(a).compareTo(band(b));
          if (byBand != 0) return byBand;
          final byScore = score(b).compareTo(score(a));
          return byScore != 0 ? byScore : measured[a].compareTo(measured[b]);
        });
      if (ranked.isEmpty) {
        // A failed ping test is not proof the server is dead (the test URL may be blocked): try connecting anyway.
        AppLog.add('ping: nothing responded, trying direct connection to the first servers');
        ranked = List.generate(pool.length < _connectAttempts ? pool.length : _connectAttempts, (i) => i);
      }

      progressTotal = 0;
      for (final i in ranked.take(_connectAttempts)) {
        _checkCancel();
        final server = pool[i];
        phase = 'اتصال به ${server.displayName}';
        notifyListeners();
        if (!await engine.connect(server, options)) {
          AppLog.add('connect: ${server.displayName} (${server.protocolLabel}) failed');
          if (!_cancel) _report(server, false, ms: measured[i]);
          continue;
        }
        AppLog.add('connect: connected to ${server.displayName} (${server.protocolLabel}, ${measured[i]} ms)');
        if (_cancel) {
          await engine.disconnect();
          throw _Cancelled();
        }
        current = server;
        currentDelay = measured[i];
        connectedAt = DateTime.now();
        state = VpnState.connected;
        phase = null;
        notifyListeners();
        _report(server, true, ms: measured[i]);
        await (await SharedPreferences.getInstance()).setString(await _networkServerKey(), server.uri);
        return;
      }
      throw const _UserError(
          'اتصال برقرار نشد. «ضد فیلتر» را روشن کنید یا کشور دیگری را امتحان کنید. جزئیات در تنظیمات ← گزارش خطا.');
    } on _Cancelled {
      await engine.disconnect();
      _markDisconnected();
    } on AdminRequiredError {
      error = 'حالت VPN کامل (TUN) دسترسی Administrator می‌خواهد. از تنظیمات «اجرای دوباره به‌عنوان ادمین» را بزنید.';
      _markDisconnected();
    } on PermissionDeniedError {
      error = 'اجازه‌ی VPN داده نشد. دوباره دکمه را بزنید و در پنجره‌ی اندروید «تأیید» را انتخاب کنید. '
          'اگر پنجره نیامد: تنظیمات گوشی ← شبکه ← VPN، و VPN دیگری را که «همیشه روشن» است خاموش کنید.';
      _markDisconnected();
    } on _UserError catch (e) {
      AppLog.add('connect: ${e.message}');
      error = e.message;
      _markDisconnected();
    } catch (e, st) {
      AppLog.add('connect: unexpected $e\n$st');
      error = 'خطای غیرمنتظره: $e';
      await engine.disconnect();
      _markDisconnected();
    }
  }

  Future<void> disconnect() async {
    if (state == VpnState.disconnected) return;
    state = VpnState.disconnecting;
    _userStopping = true;
    notifyListeners();
    try {
      await engine.disconnect();
    } finally {
      _userStopping = false;
      _markDisconnected();
    }
  }

  void _markDisconnected() {
    unawaited(usage.save());
    state = VpnState.disconnected;
    current = null;
    currentDelay = null;
    connectedAt = null;
    traffic = const TrafficStat();
    phase = null;
    progressDone = progressTotal = 0;
    notifyListeners();
  }
}
