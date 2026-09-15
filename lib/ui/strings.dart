import 'package:flutter/cupertino.dart' show CupertinoLocalizations, DefaultCupertinoLocalizations;
import 'package:flutter/material.dart';

import '../core/server.dart';

/// Minimal two-language layer. [L10n.en] is set from settings in main.dart before the app is (re)built;
/// the whole MaterialApp is keyed on the language, so every `tr` call re-evaluates after a switch.
class L10n {
  static bool en = false;

  static TextDirection get direction => en ? TextDirection.ltr : TextDirection.rtl;
  static Locale get locale => Locale(en ? 'en' : 'fa');
}

/// Picks the Persian or English text for the active language.
String tr(String fa, String en) => L10n.en ? en : fa;

/// "Back" arrow pointing toward the start edge.
IconData get backIcon => L10n.en ? Icons.arrow_back_rounded : Icons.arrow_forward_rounded;

/// Chevron pointing toward the end edge (navigation rows).
IconData get chevronEnd => L10n.en ? Icons.chevron_right_rounded : Icons.chevron_left_rounded;

/// Digits in the active language.
String digits(Object value) {
  final s = '$value';
  if (L10n.en) return s;
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  return s.replaceAllMapped(RegExp(r'[0-9]'), (m) => fa[int.parse(m[0]!)]);
}

/// "آخرین به‌روزرسانی سرورها: N دقیقه پیش" for the time the server list was last fetched.
String serversUpdatedAgo(DateTime? at) {
  if (at == null) return tr('سرورها هنوز به‌روزرسانی نشده‌اند', 'Servers not updated yet');
  final minutes = DateTime.now().difference(at).inMinutes;
  if (minutes < 1) return tr('آخرین به‌روزرسانی سرورها: همین حالا', 'Servers updated: just now');
  return tr('آخرین به‌روزرسانی سرورها: ${digits(minutes)} دقیقه پیش', 'Servers updated: $minutes min ago');
}

const Map<String, String> _enCountries = {
  'AE': 'UAE', 'AL': 'Albania', 'AM': 'Armenia', 'AR': 'Argentina', 'AT': 'Austria',
  'AU': 'Australia', 'AZ': 'Azerbaijan', 'BE': 'Belgium', 'BG': 'Bulgaria', 'BR': 'Brazil',
  'CA': 'Canada', 'CH': 'Switzerland', 'CL': 'Chile', 'CN': 'China', 'CY': 'Cyprus', 'CZ': 'Czechia',
  'DE': 'Germany', 'DK': 'Denmark', 'EE': 'Estonia', 'ES': 'Spain', 'FI': 'Finland',
  'FR': 'France', 'GB': 'United Kingdom', 'GE': 'Georgia', 'GR': 'Greece', 'HK': 'Hong Kong',
  'HR': 'Croatia', 'HU': 'Hungary', 'ID': 'Indonesia', 'IE': 'Ireland', 'IL': 'Israel',
  'IN': 'India', 'IQ': 'Iraq', 'IR': 'Iran', 'IS': 'Iceland', 'IT': 'Italy', 'JP': 'Japan',
  'KR': 'South Korea', 'KZ': 'Kazakhstan', 'LT': 'Lithuania', 'LU': 'Luxembourg', 'LV': 'Latvia',
  'MD': 'Moldova', 'MX': 'Mexico', 'MY': 'Malaysia', 'NL': 'Netherlands', 'NO': 'Norway',
  'NZ': 'New Zealand', 'OM': 'Oman', 'PH': 'Philippines', 'PK': 'Pakistan', 'PL': 'Poland',
  'PT': 'Portugal', 'QA': 'Qatar', 'RO': 'Romania', 'RS': 'Serbia', 'RU': 'Russia',
  'SA': 'Saudi Arabia', 'SC': 'Seychelles', 'SE': 'Sweden', 'SG': 'Singapore', 'SI': 'Slovenia',
  'SK': 'Slovakia', 'TH': 'Thailand', 'TR': 'Turkey', 'TW': 'Taiwan', 'UA': 'Ukraine',
  'US': 'United States', 'VN': 'Vietnam', 'ZA': 'South Africa',
  'ZZ': 'My configs', 'UN': 'Unknown', 'WARP': 'Cloudflare WARP', 'FAV': 'Favorites',
};

/// Country name for [code]; [faName] is the Persian name the core already computed.
String countryText(String code, String faName) => L10n.en ? (_enCountries[code] ?? code) : faName;

/// Server title ("Germany 03") in the active language.
String serverTitle(Server s) {
  if (!L10n.en) return s.displayName;
  final fa = s.countryLabel;
  final en = _enCountries[s.countryCode] ?? s.countryCode;
  return s.displayName.startsWith(fa) ? en + s.displayName.substring(fa.length) : s.displayName;
}

/// Fallback localizations so a Persian locale works without the flutter_localizations package:
/// English Material/Cupertino texts, but right-to-left widget direction.
class AppLocalizationDelegates {
  static const List<LocalizationsDelegate<dynamic>> all = [
    _MaterialFallback(),
    _WidgetsFallback(),
    _CupertinoFallback(),
  ];
  static const supportedLocales = [Locale('fa'), Locale('en')];
}

class _MaterialFallback extends LocalizationsDelegate<MaterialLocalizations> {
  const _MaterialFallback();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<MaterialLocalizations> load(Locale locale) => DefaultMaterialLocalizations.load(locale);
  @override
  bool shouldReload(_MaterialFallback old) => false;
}

class _CupertinoFallback extends LocalizationsDelegate<CupertinoLocalizations> {
  const _CupertinoFallback();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<CupertinoLocalizations> load(Locale locale) => DefaultCupertinoLocalizations.load(locale);
  @override
  bool shouldReload(_CupertinoFallback old) => false;
}

class _WidgetsFallback extends LocalizationsDelegate<WidgetsLocalizations> {
  const _WidgetsFallback();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<WidgetsLocalizations> load(Locale locale) async =>
      locale.languageCode == 'fa' ? const _RtlWidgetsLocalizations() : const DefaultWidgetsLocalizations();
  @override
  bool shouldReload(_WidgetsFallback old) => false;
}

class _RtlWidgetsLocalizations extends DefaultWidgetsLocalizations {
  const _RtlWidgetsLocalizations();
  @override
  TextDirection get textDirection => TextDirection.rtl;
}
