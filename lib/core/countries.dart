/// Country code -> Persian display name and flag emoji.
const Map<String, String> _faNames = {
  'AE': 'امارات', 'AL': 'آلبانی', 'AM': 'ارمنستان', 'AR': 'آرژانتین', 'AT': 'اتریش',
  'AU': 'استرالیا', 'AZ': 'آذربایجان', 'BE': 'بلژیک', 'BG': 'بلغارستان', 'BR': 'برزیل',
  'CA': 'کانادا', 'CH': 'سوئیس', 'CL': 'شیلی', 'CN': 'چین', 'CY': 'قبرس', 'CZ': 'چک',
  'DE': 'آلمان', 'DK': 'دانمارک', 'EE': 'استونی', 'ES': 'اسپانیا', 'FI': 'فنلاند',
  'FR': 'فرانسه', 'GB': 'انگلستان', 'GE': 'گرجستان', 'GR': 'یونان', 'HK': 'هنگ‌کنگ',
  'HR': 'کرواسی', 'HU': 'مجارستان', 'ID': 'اندونزی', 'IE': 'ایرلند', 'IL': 'اسرائیل',
  'IN': 'هند', 'IQ': 'عراق', 'IR': 'ایران', 'IS': 'ایسلند', 'IT': 'ایتالیا', 'JP': 'ژاپن',
  'KR': 'کره جنوبی', 'KZ': 'قزاقستان', 'LT': 'لیتوانی', 'LU': 'لوکزامبورگ', 'LV': 'لتونی',
  'MD': 'مولداوی', 'MX': 'مکزیک', 'MY': 'مالزی', 'NL': 'هلند', 'NO': 'نروژ',
  'NZ': 'نیوزیلند', 'OM': 'عمان', 'PH': 'فیلیپین', 'PK': 'پاکستان', 'PL': 'لهستان',
  'PT': 'پرتغال', 'QA': 'قطر', 'RO': 'رومانی', 'RS': 'صربستان', 'RU': 'روسیه',
  'SA': 'عربستان', 'SC': 'سیشل', 'SE': 'سوئد', 'SG': 'سنگاپور', 'SI': 'اسلوونی',
  'SK': 'اسلواکی', 'TH': 'تایلند', 'TR': 'ترکیه', 'TW': 'تایوان', 'UA': 'اوکراین',
  'US': 'آمریکا', 'VN': 'ویتنام', 'ZA': 'آفریقای جنوبی',
};

const unknownCountry = 'UN';

String countryName(String code) => _faNames[code] ?? (code == unknownCountry ? 'نامشخص' : code);

String flagEmoji(String code) {
  if (code.length != 2 || code == unknownCountry) return '🌐';
  return String.fromCharCodes(code.toUpperCase().codeUnits.map((c) => 0x1F1E6 + c - 0x41));
}

/// Reads the first flag emoji (two regional-indicator symbols) in [text] back into a country code.
String countryCodeFromText(String text) {
  final runes = text.runes.toList();
  for (var i = 0; i + 1 < runes.length; i++) {
    final a = runes[i], b = runes[i + 1];
    if (_isRegional(a) && _isRegional(b)) {
      return String.fromCharCodes([a - 0x1F1E6 + 0x41, b - 0x1F1E6 + 0x41]);
    }
  }
  return unknownCountry;
}

bool _isRegional(int r) => r >= 0x1F1E6 && r <= 0x1F1FF;
