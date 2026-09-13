import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_log.dart';

enum AccountStatus { loading, signedOut, ok, disabled, otherDevice }

/// Supabase accounts: sign-up / sign-in, one device per account, on/off switch and usage reporting
/// (managed from the admin panel). Without SUPABASE_URL / SUPABASE_ANON_KEY at build time accounts are off
/// and the app works as before.
class Account extends ChangeNotifier {
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _deviceKey = 'account_device_id', _statusKey = 'account_last_status';

  static bool get configured => _url.isNotEmpty && _anonKey.isNotEmpty;

  AccountStatus status = configured ? AccountStatus.loading : AccountStatus.ok;
  late String deviceId;

  SupabaseClient get _client => Supabase.instance.client;

  User? get user => configured ? _client.auth.currentUser : null;
  String get displayName => '${user?.userMetadata?['full_name'] ?? ''}'.trim();

  static String get deviceName =>
      '${Platform.isAndroid ? 'Android' : Platform.isWindows ? 'Windows' : Platform.operatingSystem} · ${Platform.localHostname}';

  Future<void> init() async {
    if (!configured) return;
    final prefs = await SharedPreferences.getInstance();
    deviceId = prefs.getString(_deviceKey) ?? _newDeviceId();
    await prefs.setString(_deviceKey, deviceId);
    try {
      await Supabase.initialize(url: _url, publishableKey: _anonKey);
      _client.auth.onAuthStateChange.listen((_) => refreshStatus());
    } catch (e) {
      AppLog.add('account: init failed: $e');
    }
    await refreshStatus();
  }

  static String _newDeviceId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  void _set(AccountStatus next) {
    if (status == next) return;
    status = next;
    notifyListeners();
  }

  /// Asks the server whether this account may be used on this device (binds it on first use).
  /// Offline, the last known answer is kept so the app still works when Supabase is unreachable.
  Future<AccountStatus> refreshStatus() async {
    if (!configured) return status;
    final prefs = await SharedPreferences.getInstance();
    if (_client.auth.currentSession == null) {
      _set(AccountStatus.signedOut);
      return status;
    }
    try {
      final result = await _client
          .rpc<String>('claim_device', params: {'p_device_id': deviceId, 'p_device_name': deviceName})
          .timeout(const Duration(seconds: 12));
      _set(_parse(result));
      await prefs.setString(_statusKey, status.name);
    } catch (e) {
      AppLog.add('account: status check failed ($e), using cached status');
      final cached = prefs.getString(_statusKey);
      _set(AccountStatus.values.where((s) => s.name == cached).firstOrNull ?? AccountStatus.ok);
    }
    return status;
  }

  static AccountStatus _parse(String? result) => switch (result) {
        'disabled' => AccountStatus.disabled,
        'other_device' => AccountStatus.otherDevice,
        _ => AccountStatus.ok,
      };

  /// Adds used traffic to the account. Returns the account status reported by the server.
  Future<AccountStatus> reportUsage(int up, int down) async {
    if (!configured || _client.auth.currentSession == null) return status;
    try {
      final result = await _client.rpc<String>('report_usage',
          params: {'p_device_id': deviceId, 'p_up': up, 'p_down': down}).timeout(const Duration(seconds: 12));
      _set(_parse(result));
    } catch (e) {
      AppLog.add('account: usage report failed: $e');
    }
    return status;
  }

  /// Returns null on success, otherwise a message for the user.
  Future<String?> signIn(String email, String password) => _guard(() async {
        await _client.auth.signInWithPassword(email: email.trim(), password: password);
        await refreshStatus();
      });

  /// Returns null on success, 'confirm' when the email must be confirmed first, otherwise a message.
  Future<String?> signUp(String name, String email, String password) => _guard(() async {
        final res = await _client.auth.signUp(email: email.trim(), password: password, data: {'full_name': name.trim()});
        if (res.session == null) throw const AuthException('confirm');
        await refreshStatus();
      });

  Future<String?> resetPassword(String email) => _guard(() => _client.auth.resetPasswordForEmail(email.trim()));

  Future<void> signOut() async {
    if (!configured) return;
    try {
      await _client.auth.signOut();
    } finally {
      _set(AccountStatus.signedOut);
    }
  }

  Future<String?> _guard(Future<void> Function() action) async {
    try {
      await action();
      return null;
    } on AuthException catch (e) {
      AppLog.add('account: ${e.message}');
      final m = e.message.toLowerCase();
      if (m == 'confirm') return 'confirm';
      if (m.contains('invalid login')) return 'ایمیل یا رمز عبور اشتباه است.';
      if (m.contains('already registered')) return 'با این ایمیل قبلاً ثبت‌نام شده؛ وارد شوید.';
      if (m.contains('password')) return 'رمز عبور باید دست‌کم ۶ کاراکتر باشد.';
      if (m.contains('email not confirmed')) return 'ایمیل هنوز تأیید نشده؛ صندوق ایمیل را ببینید.';
      return 'خطا: ${e.message}';
    } catch (e) {
      AppLog.add('account: $e');
      return 'به سرور حساب‌ها وصل نشد. اینترنت را بررسی کنید (در صورت نیاز با VPN دیگری امتحان کنید).';
    }
  }
}
