import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_log.dart';
import 'countries.dart';

/// The device's current network: connection type, carrier/ISP and public IP.
/// Before connecting this is the user's own internet; while connected the IP is the VPN exit.
class NetworkInfo extends ChangeNotifier {
  static const _channel = MethodChannel('mobin/native');

  String? type; // wifi | mobile | ethernet | none (Android only)
  String? carrier; // SIM operator name from Android
  String? ip, isp, countryCode;
  bool loading = false;

  String get typeLabel => switch (type) {
        'wifi' => 'وای‌فای',
        'mobile' => 'دیتای موبایل',
        'ethernet' => 'اینترنت کابلی',
        'none' => 'بدون اینترنت',
        _ => 'اینترنت',
      };

  /// Persian name of well-known Iranian operators and ISPs, otherwise the raw name.
  String get providerLabel {
    final raw = '${isp ?? ''} ${type == 'mobile' ? carrier ?? '' : ''}'.toLowerCase();
    const known = {
      'mobile communication company of iran': 'همراه اول',
      'mci': 'همراه اول',
      'hamrah': 'همراه اول',
      'irancell': 'ایرانسل',
      'mtn': 'ایرانسل',
      'rightel': 'رایتل',
      'telecommunication company of iran': 'مخابرات',
      'tci': 'مخابرات',
      'shatel': 'شاتل',
      'asiatech': 'آسیاتک',
      'pars online': 'پارس‌آنلاین',
      'parsonline': 'پارس‌آنلاین',
      'mobinnet': 'مبین‌نت',
      'respina': 'رسپینا',
      'hiweb': 'های‌وب',
      'pishgaman': 'پیشگامان',
      'afranet': 'افرانت',
      'cloudflare': 'Cloudflare WARP',
    };
    for (final e in known.entries) {
      if (raw.contains(e.key)) return e.value;
    }
    return (isp?.isNotEmpty ?? false) ? isp! : (carrier ?? 'نامشخص');
  }

  String get countryLabel => countryCode == null ? '' : countryName(countryCode!);

  Future<void> refresh({String? proxy}) async {
    if (loading) return;
    loading = true;
    notifyListeners();
    try {
      if (Platform.isAndroid) {
        final m = await _channel.invokeMapMethod<String, dynamic>('networkInfo');
        type = m?['type'] as String?;
        carrier = (m?['operator'] as String?)?.trim();
      }
      await _lookupIp(proxy);
    } catch (e) {
      AppLog.add('network info: $e');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _lookupIp(String? proxy) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    if (proxy != null) client.findProxy = (_) => 'PROXY $proxy';
    try {
      for (final url in ['https://ipwho.is/', 'http://ip-api.com/json/?fields=query,isp,countryCode']) {
        try {
          final res = await (await client.getUrl(Uri.parse(url))).close().timeout(const Duration(seconds: 10));
          final j = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
          ip = (j['ip'] ?? j['query']) as String?;
          isp = ((j['connection'] as Map?)?['isp'] ?? j['isp']) as String?;
          countryCode = (j['country_code'] ?? j['countryCode']) as String?;
          if (ip != null) return;
        } catch (_) {}
      }
    } finally {
      client.close(force: true);
    }
  }
}
