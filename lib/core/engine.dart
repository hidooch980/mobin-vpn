import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'android_engine.dart';
import 'server.dart';
import 'windows_engine.dart';

enum VpnState { disconnected, connecting, connected, disconnecting }

class TrafficStat {
  const TrafficStat({this.up = 0, this.down = 0});

  /// Bytes per second.
  final int up, down;
}

class PermissionDeniedError implements Exception {
  const PermissionDeniedError();
}

class AdminRequiredError implements Exception {
  const AdminRequiredError();
}

class EngineOptions {
  const EngineOptions({
    this.testUrl = 'https://www.gstatic.com/generate_204',
    this.timeout = const Duration(seconds: 8),
    this.proxyOnly = false,
    this.systemProxy = true,
    this.tunMode = false,
    this.killSwitch = false,
    this.localPort = 0,
    this.bypassIran = true,
    this.dns = '1.1.1.1',
    this.fragment = false,
    this.excludedApps = const [],
  });

  final String testUrl;
  final Duration timeout;
  final bool proxyOnly, systemProxy, tunMode, killSwitch, bypassIran, fragment;
  final int localPort;
  final String dns;
  final List<String> excludedApps;

  /// Settings that change the generated core config.
  String get configKey => '$dns|$bypassIran|$fragment';
}

/// Platform VPN core. Delays are measured from the user's own connection.
abstract class VpnEngine {
  static VpnEngine create() => Platform.isWindows ? WindowsEngine() : AndroidEngine();

  /// Emits when the tunnel stops on its own (killed, notification button...).
  Stream<VpnState> get states;
  Stream<TrafficStat> get traffic;

  /// Local HTTP proxy "host:port" while connected, for the app's own requests (Windows only).
  String? get httpProxy;

  bool supports(Server server);
  Future<void> init();

  /// Real delay in ms for each server (same order), -1 when it failed.
  Future<List<int>> pingAll(List<Server> servers, EngineOptions options,
      {void Function(int done)? onProgress, bool Function()? isCancelled});

  /// Starts the tunnel and returns true only once traffic really passes through it.
  Future<bool> connect(Server server, EngineOptions options);
  Future<void> disconnect();
}

/// Runs [task] for 0..count-1 with at most [concurrency] in flight.
Future<List<int>> runPool(int count, int concurrency, Future<int> Function(int index) task,
    {void Function(int done)? onProgress}) async {
  final results = List<int>.filled(count, -1);
  var next = 0, done = 0;
  Future<void> worker() async {
    while (next < count) {
      final i = next++;
      try {
        results[i] = await task(i);
      } catch (_) {
        results[i] = -1;
      }
      onProgress?.call(++done);
    }
  }

  await Future.wait(List.generate(math.min(concurrency, count), (_) => worker()));
  return results;
}
