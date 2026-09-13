import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'countries.dart';
import 'engine.dart';
import 'server.dart';
import 'settings.dart';
import 'subscription.dart';
import 'updater.dart';
import 'usage_stats.dart';

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
      : engine = engine ?? VpnEngine.create(),
        repository = repository ?? SubscriptionRepository();

  final VpnEngine engine;
  final SubscriptionRepository repository;
  final settings = AppSettings();
  final updater = Updater();
  final usage = UsageStats();

  static const _countryKey = 'country', _lastServerKey = 'last_server';
  static const _countryPoolSize = 30, _connectAttempts = 4;

  /// Pseudo location: low, stable ping from servers geographically close to Iran.
  static const gamingMode = 'GAME';
  static const _nearIran = [
    'TR', 'AE', 'AM', 'GE', 'AZ', 'QA', 'OM', 'BH', 'SA', 'KZ', 'CY', 'RU', 'BG', 'RO', 'GR', 'UA',
    'DE', 'AT', 'NL', 'FR', 'IT', 'PL', 'FI', 'SE', 'CH', 'GB', 'ES',
  ];
  static const _gamingRefine = 8, _gamingRounds = 2;

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
    } catch (e) {
      error = 'راه‌اندازی هسته ناموفق بود: $e';
    }
    final cached = await repository.loadCached();
    if (cached != null) _apply(cached);
    await refresh();
    if (settings.connectOnLaunch && servers.isNotEmpty) unawaited(connect());
    await checkUpdate();
  }

  void _apply(SubscriptionData data) {
    _data = data;
    servers = data.servers.where((s) => settings.protocols.contains(s.protocol) && engine.supports(s)).toList();
    final groups = <String, CountryGroup>{};
    for (final s in servers) {
      groups.putIfAbsent(s.countryCode, () => CountryGroup(s.countryCode)).servers.add(s);
    }
    countries = groups.values.toList();
    if (selectedCountry != null && !isGaming && !groups.containsKey(selectedCountry)) selectedCountry = null;
    updatedAt = data.updatedAt;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      _apply(await repository.fetch(customUrl: settings.customSubscription));
    } catch (_) {
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
    if (lastServer != null && !pool.contains(lastServer) && (country == null || lastServer.countryCode == country)) {
      pool.insert(0, lastServer);
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
    final options = _options;
    try {
      if (servers.isEmpty && only == null) await refresh();
      final List<Server> pool = only != null ? [only] : await _candidates();
      if (pool.isEmpty) throw const _UserError('سروری برای این موقعیت پیدا نشد.');

      phase = 'سنجش سرورها با اینترنت شما';
      progressTotal = pool.length;
      notifyListeners();
      final measured = await engine.pingAll(pool, options, isCancelled: () => _cancel, onProgress: (done) {
        progressDone = done;
        notifyListeners();
      });
      _checkCancel();
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
        throw _UserError(only != null
            ? 'این سرور با اینترنت شما پاسخ نداد.'
            : 'هیچ سروری با اینترنت شما پاسخ نداد. کمی بعد دوباره امتحان کنید.');
      }

      progressTotal = 0;
      for (final i in ranked.take(_connectAttempts)) {
        _checkCancel();
        final server = pool[i];
        phase = 'اتصال به ${server.displayName}';
        notifyListeners();
        if (!await engine.connect(server, options)) continue;
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
      throw const _UserError('اتصال برقرار نشد. دوباره تلاش کنید.');
    } on _Cancelled {
      _markDisconnected();
    } on AdminRequiredError {
      error = 'حالت VPN کامل (TUN) دسترسی Administrator می‌خواهد. از تنظیمات «اجرای دوباره به‌عنوان ادمین» را بزنید.';
      _markDisconnected();
    } on PermissionDeniedError {
      error = 'برای اتصال، اجازه‌ی VPN لازم است.';
      _markDisconnected();
    } on _UserError catch (e) {
      error = e.message;
      _markDisconnected();
    } catch (e) {
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
