import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'countries.dart';
import 'engine.dart';
import 'server.dart';
import 'subscription.dart';
import 'updater.dart';

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

  static const _countryKey = 'country', _lastServerKey = 'last_server';
  static const _autoPoolSize = 40, _countryPoolSize = 30, _connectAttempts = 4;

  List<Server> servers = const [];
  List<CountryGroup> countries = const [];

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
  bool loading = false;
  String? error;
  bool _cancel = false;

  final updater = Updater();
  UpdateInfo? update;

  /// null = not downloading.
  double? updateProgress;

  double? get progress => progressTotal == 0 ? null : progressDone / progressTotal;

  Future<void> init() async {
    engine.states.listen((s) {
      if (s == VpnState.disconnected && state == VpnState.connected) _markDisconnected();
    });
    engine.traffic.listen((t) {
      if (state != VpnState.connected) return;
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
    await checkUpdate();
  }

  Future<void> checkUpdate() async {
    try {
      update = await updater.check(proxy: engine.httpProxy);
      notifyListeners();
    } catch (_) {
      // Offline or GitHub blocked: try again next launch.
    }
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

  void _apply(SubscriptionData data) {
    servers = data.servers.where(engine.supports).toList();
    final groups = <String, CountryGroup>{};
    for (final s in servers) {
      groups.putIfAbsent(s.countryCode, () => CountryGroup(s.countryCode)).servers.add(s);
    }
    countries = groups.values.toList();
    if (selectedCountry != null && !groups.containsKey(selectedCountry)) selectedCountry = null;
    updatedAt = data.updatedAt;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      _apply(await repository.fetch());
    } catch (_) {
      if (servers.isEmpty) error = 'دریافت لیست سرورها ناموفق بود. اینترنت را بررسی کنید.';
    } finally {
      loading = false;
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

  void _checkCancel() {
    if (_cancel) throw _Cancelled();
  }

  Future<List<Server>> _candidates() async {
    final List<Server> pool;
    final country = selectedCountry;
    if (country != null) {
      pool = servers.where((s) => s.countryCode == country).take(_countryPoolSize).toList();
    } else {
      // Round-robin across countries so auto mode compares many locations, not only the first one.
      pool = [];
      for (var round = 0; pool.length < _autoPoolSize; round++) {
        var added = false;
        for (final g in countries) {
          if (round < g.servers.length && pool.length < _autoPoolSize) {
            pool.add(g.servers[round]);
            added = true;
          }
        }
        if (!added) break;
      }
    }
    final last = (await SharedPreferences.getInstance()).getString(_lastServerKey);
    final lastServer = servers.where((s) => s.uri == last).firstOrNull;
    if (lastServer != null && !pool.contains(lastServer) && (country == null || lastServer.countryCode == country)) {
      pool.insert(0, lastServer);
    }
    return pool;
  }

  Future<void> connect() async {
    if (state != VpnState.disconnected) return;
    error = null;
    _cancel = false;
    state = VpnState.connecting;
    phase = 'در حال آماده‌سازی…';
    progressDone = progressTotal = 0;
    notifyListeners();
    try {
      if (servers.isEmpty) await refresh();
      final pool = await _candidates();
      if (pool.isEmpty) throw const _UserError('سروری برای این موقعیت پیدا نشد.');

      phase = 'سنجش سرورها با اینترنت شما';
      progressTotal = pool.length;
      notifyListeners();
      final delays = await engine.pingAll(pool, isCancelled: () => _cancel, onProgress: (done) {
        progressDone = done;
        notifyListeners();
      });
      _checkCancel();

      final ranked = [for (var i = 0; i < pool.length; i++) if (delays[i] > 0) i]
        ..sort((a, b) => delays[a].compareTo(delays[b]));
      if (ranked.isEmpty) throw const _UserError('هیچ سروری با اینترنت شما پاسخ نداد. کمی بعد دوباره امتحان کنید.');

      progressTotal = 0;
      for (final i in ranked.take(_connectAttempts)) {
        _checkCancel();
        final server = pool[i];
        phase = 'اتصال به ${server.displayName}';
        notifyListeners();
        if (!await engine.connect(server)) continue;
        if (_cancel) {
          await engine.disconnect();
          throw _Cancelled();
        }
        current = server;
        currentDelay = delays[i];
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
    notifyListeners();
    try {
      await engine.disconnect();
    } finally {
      _markDisconnected();
    }
  }

  void _markDisconnected() {
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
