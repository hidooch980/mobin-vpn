import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';
import 'countries.dart';
import 'engine.dart';
import 'server.dart';
import 'settings.dart';
import 'subscription.dart';
import 'update_notifier.dart';
import 'updater.dart';
import 'usage_stats.dart';
import 'warp.dart';

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

  static const _countryKey = 'country', _lastServerKey = 'last_server';
  static const _countryPoolSize = 30, _connectAttempts = 4;

  /// Completes once settings, cache and the first server refresh are done.
  final ready = Completer<void>();

  /// Pseudo location: starred servers only.
  static const favoritesMode = 'FAV';

  /// Country code given to user-imported configs (shown as "کانفیگ‌های من").
  static const manualCode = 'ZZ';

  /// Pseudo location: low, stable ping from servers geographically close to Iran.
  static const gamingMode = 'GAME';
  static const _nearIran = [
    'TR', 'AE', 'AM', 'GE', 'AZ', 'QA', 'OM', 'BH', 'SA', 'KZ', 'CY', 'RU', 'BG', 'RO', 'GR', 'UA',
    'DE', 'AT', 'NL', 'FR', 'IT', 'PL', 'FI', 'SE', 'CH', 'GB', 'ES',
  ];
  static const _gamingRefine = 8, _gamingRounds = 2;

  /// Smart mode stops pinging after this many responsive servers (Android pings one by one, so stop at the first).
  static int get _enoughGood => Platform.isAndroid ? 1 : 3;

  bool get isGaming => selectedCountry == gamingMode;

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
      );

  Future<void> init() async {
    await Future.wait([settings.load(), usage.load()]);
    settings.addListener(() {
      final data = _data;
      if (data != null) _apply(data);
    });
    engine.states.listen((s) {
      if (s != VpnState.disconnected || state != VpnState.connected || _userStopping) return;
      _markDisconnected();
      if (settings.autoReconnect) {
        error = 'اتصال قطع شد؛ در حال اتصال دوباره…';
        unawaited(connect());
      }
    });
    engine.traffic.listen((t) {
      if (state != VpnState.connected) return;
      usage.add(t);
      traffic = t;
      notifyListeners();
    });
    final prefs = await SharedPreferences.getInstance();
    selectedCountry = prefs.getString(_countryKey);
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
    if (!ready.isCompleted) ready.complete();
    if (settings.connectOnLaunch && servers.isNotEmpty) unawaited(connect());
    await checkUpdate();
    // Long-running sessions (e.g. Windows left open) still hear about new releases.
    Timer.periodic(const Duration(hours: 6), (_) => checkUpdate());
  }

  void _apply(SubscriptionData data) {
    _data = data;
    final manual = [
      for (final link in settings.manualConfigs)
        if (Server.fromUri(link) case final s?)
          Server(uri: s.uri, remark: s.remark, countryCode: manualCode, protocol: s.protocol),
    ].where(engine.supports);
    servers = [
      ...manual,
      ...data.servers.where((s) => settings.protocols.contains(s.protocol) && engine.supports(s)),
    ];
    final groups = <String, CountryGroup>{};
    for (final s in servers) {
      groups.putIfAbsent(s.countryCode, () => CountryGroup(s.countryCode)).servers.add(s);
    }
    countries = groups.values.toList();
    if (selectedCountry != null &&
        !isGaming &&
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
      error = 'به‌روزرسانی ناموفق بود. اگر گیت‌هاب باز نمی‌شود، اول وصل شوید و دوباره امتحان کنید.';
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
        _cancel = true;
        phase = 'در حال لغو…';
        notifyListeners();
      case VpnState.disconnected:
        await connect();
      case VpnState.disconnecting:
        break;
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

  /// Gaming: re-test the fastest few and rank by average + jitter, not a single lucky ping.
  Future<List<int>> _gamingScores(List<Server> pool, List<int> measured, List<int> ranked, EngineOptions options) async {
    final top = ranked.take(_gamingRefine).toList();
    final samples = {for (final i in top) i: [measured[i]]};
    for (var round = 0; round < _gamingRounds; round++) {
      _checkCancel();
      phase = 'سنجش پایداری پینگ برای بازی (${round + 1}/$_gamingRounds)';
      notifyListeners();
      final again = await engine.pingAll([for (final i in top) pool[i]], options, isCancelled: () => _cancel);
      for (var k = 0; k < top.length; k++) {
        samples[top[k]]!.add(again[k]);
      }
    }
    final scores = List<int>.filled(pool.length, -1);
    for (final e in samples.entries) {
      final ok = e.value.where((d) => d > 0).toList();
      if (ok.length < e.value.length) continue; // any lost probe = unstable for games
      final avg = ok.reduce((a, b) => a + b) ~/ ok.length;
      final jitter = ok.reduce((a, b) => a > b ? a : b) - ok.reduce((a, b) => a < b ? a : b);
      scores[e.key] = avg + jitter * 2;
    }
    return scores;
  }

  Future<List<Server>> _candidates() async {
    final List<Server> pool;
    final country = selectedCountry;
    final size = settings.poolSize;
    if (country == favoritesMode) {
      return servers.where((s) => settings.favorites.contains(s.uri)).toList();
    }
    if (country == gamingMode) {
      final near = [
        for (final code in _nearIran) ...countries.where((g) => g.code == code),
      ];
      return _roundRobin(near.isEmpty ? countries : near, size);
    }
    if (country != null) {
      pool = servers.where((s) => s.countryCode == country).take(_countryPoolSize).toList();
    } else {
      pool = _roundRobin(countries, size);
    }
    final last = (await SharedPreferences.getInstance()).getString(_lastServerKey);
    final lastServer = servers.where((s) => s.uri == last).firstOrNull;
    if (lastServer != null && (country == null || lastServer.countryCode == country)) {
      pool
        ..remove(lastServer)
        ..insert(0, lastServer);
    }
    return pool;
  }

  Future<void> connect({Server? only}) async {
    if (state != VpnState.disconnected) return;
    error = null;
    _cancel = false;
    state = VpnState.connecting;
    phase = 'در حال آماده‌سازی…';
    progressDone = progressTotal = 0;
    notifyListeners();
    var options = _options;
    try {
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
      final List<Server> pool = only != null ? [only] : await _candidates();
      if (pool.isEmpty) throw const _UserError('سروری برای این موقعیت پیدا نشد.');

      // Fast path like v2rayNG: reconnect straight to the last working server, no ping round.
      final last = (await SharedPreferences.getInstance()).getString(_lastServerKey);
      if (only == null && !isGaming && pool.isNotEmpty && pool.first.uri == last) {
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
          return;
        }
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
          await (await SharedPreferences.getInstance()).setString(_lastServerKey, only.uri);
          return;
        }
        throw const _UserError('این سرور وصل نشد. سرور دیگری را امتحان کنید.');
      }

      phase = 'سنجش سرورها با اینترنت شما';
      progressTotal = pool.length;
      notifyListeners();
      AppLog.add('connect: mode=${selectedCountry ?? 'auto'} pool=${pool.length} platform=${Platform.operatingSystem}');
      // Smart/country modes stop testing once a few good servers are found — much faster, especially on Android.
      final canStopEarly = only == null && !isGaming;
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
          notifyListeners();
        },
      );
      _checkCancel();
      AppLog.add('ping: ${measured.where((d) => d > 0).length}/${pool.length} responded '
          '(best ${measured.where((d) => d > 0).fold<int?>(null, (a, d) => a == null || d < a ? d : a)} ms)');
      for (var i = 0; i < pool.length; i++) {
        delays[pool[i].uri] = measured[i];
      }

      var ranked = [for (var i = 0; i < pool.length; i++) if (measured[i] > 0) i]
        ..sort((a, b) => measured[a].compareTo(measured[b]));
      if (only == null && isGaming && ranked.length > 1) {
        final scores = await _gamingScores(pool, measured, ranked, options);
        final stable = [for (final i in ranked) if (scores[i] > 0) i]..sort((a, b) => scores[a].compareTo(scores[b]));
        if (stable.isNotEmpty) ranked = stable;
      }
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
        await (await SharedPreferences.getInstance()).setString(_lastServerKey, server.uri);
        return;
      }
      throw const _UserError(
          'اتصال برقرار نشد. «ضد فیلتر» را روشن کنید یا کشور دیگری را امتحان کنید. جزئیات در تنظیمات ← گزارش خطا.');
    } on _Cancelled {
      _markDisconnected();
    } on AdminRequiredError {
      error = 'حالت VPN کامل (TUN) دسترسی Administrator می‌خواهد. از تنظیمات «اجرای دوباره به‌عنوان ادمین» را بزنید.';
      _markDisconnected();
    } on PermissionDeniedError {
      error = 'برای اتصال، اجازه‌ی VPN لازم است.';
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
