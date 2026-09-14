import 'package:flutter/material.dart';

import '../core/vpn_controller.dart';
import 'flag_badge.dart';
import 'strings.dart';
import 'style.dart';
import 'widgets.dart';

Future<void> showLocationSheet(BuildContext context, VpnController controller) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => _LocationSheet(controller: controller),
  );
}

/// Human label of the selected location (null = smart).
String locationLabel(VpnController c) => switch (c.selectedCountry) {
      null => tr('هوشمند', 'Smart'),
      VpnController.favoritesMode => tr('علاقه‌مندی‌ها', 'Favorites'),
      final String code => countryText(code, c.countries.where((g) => g.code == code).firstOrNull?.name ?? code),
    };

class _LocationSheet extends StatefulWidget {
  const _LocationSheet({required this.controller});

  final VpnController controller;

  @override
  State<_LocationSheet> createState() => _LocationSheetState();
}

class _LocationSheetState extends State<_LocationSheet> {
  String _query = '';

  void _pick(String? code) {
    Navigator.of(context).pop();
    final c = widget.controller;
    // Countries and favorites need the V2Ray server list; a serverless route (WARP only) would ignore them.
    if (code != null && (c.settings.transport == 'warp' || c.settings.transport == 'psiphon' || c.settings.transport == 'tor')) {
      c.settings.update((x) => x.transport = 'auto');
    }
    c.selectCountry(code);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final q = _query.trim().toLowerCase();
    final groups = c.countries
        .where((g) =>
            q.isEmpty || g.name.contains(q) || countryText(g.code, g.name).toLowerCase().contains(q) || g.code.toLowerCase().contains(q))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scroll) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: kContentWidth + 40),
          child: Container(
            decoration: BoxDecoration(
              color: Palette.bg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(Palette.cardRadius)),
            ),
            child: Column(children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Palette.border, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 14),
              Text(tr('انتخاب موقعیت', 'Choose location'), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: Palette.text)),
              const SizedBox(height: 4),
              Text(tr('${c.servers.length} سرور تست‌شده در ${c.countries.length} کشور', '${c.servers.length} tested servers in ${c.countries.length} countries'), style: TextStyle(fontSize: 13, color: Palette.muted)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(color: Palette.text),
                  decoration: InputDecoration(
                    hintText: tr('جستجوی کشور…', 'Search country…'),
                    hintStyle: TextStyle(color: Palette.muted),
                    prefixIcon: Icon(Icons.search_rounded, color: Palette.muted),
                    filled: true,
                    fillColor: Palette.surface,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    enabledBorder:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(Palette.pillRadius), borderSide: Palette.cardSide),
                    focusedBorder:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Palette.accent)),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  children: [
                    if (q.isEmpty) ...[
                      SectionHeader(tr('حالت‌ها', 'Modes')),
                      _Tile(
                        code: null,
                        title: tr('هوشمند', 'Smart'),
                        subtitle: tr('اتصال خودکار به سریع‌ترین سرور برای اینترنت شما', 'Connects to the fastest server for your internet'),
                        selected: c.selectedCountry == null,
                        onTap: () => _pick(null),
                      ),
                      if (c.settings.favorites.isNotEmpty)
                        _Tile(
                          code: VpnController.favoritesMode,
                          title: tr('علاقه‌مندی‌ها', 'Favorites'),
                          subtitle: tr('${c.settings.favorites.length} سرور ستاره‌دار · سریع‌ترین انتخاب می‌شود',
                              '${c.settings.favorites.length} starred servers · fastest is used'),
                          selected: c.selectedCountry == VpnController.favoritesMode,
                          onTap: () => _pick(VpnController.favoritesMode),
                        ),
                      SectionHeader(tr('کشورها', 'Countries')),
                    ],
                    for (final g in groups)
                      _Tile(
                        code: g.code,
                        title: countryText(g.code, g.name),
                        subtitle: tr('${g.servers.length} سرور', '${g.servers.length} servers'),
                        selected: c.selectedCountry == g.code,
                        onTap: () => _pick(g.code),
                      ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.code, required this.title, required this.subtitle, required this.selected, required this.onTap});

  final String? code;
  final String title, subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: AppCard(
        onTap: onTap,
        borderColor: selected ? Palette.accent : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(children: [
          FlagBadge(code: code, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: Palette.text)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12.5, color: Palette.muted)),
            ]),
          ),
          selected
              ? Icon(Icons.check_circle_rounded, color: Palette.accent)
              : Icon(chevronEnd, color: Palette.muted),
        ]),
      ),
    );
  }
}
