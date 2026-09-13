import 'package:flutter/material.dart';
import 'package:installed_apps/app_info.dart';
import 'package:installed_apps/installed_apps.dart';

import '../core/engine.dart';
import '../core/settings.dart';
import 'aurora_background.dart';
import 'glass.dart';
import 'style.dart';

/// Android split tunneling: checked apps bypass the VPN.
class AppsScreen extends StatefulWidget {
  const AppsScreen({super.key, required this.settings});

  final AppSettings settings;

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  late final Future<List<AppInfo>> _apps = InstalledApps.getInstalledApps(withIcon: true)
      .then((list) => list..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Scaffold(
      body: AuroraBackground(
        colors: Palette.forState(VpnState.disconnected),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(children: [
                  Glass(
                    radius: 16,
                    padding: const EdgeInsets.all(10),
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(Icons.arrow_forward_rounded, color: Palette.text),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('برنامه‌های خارج از VPN', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Palette.text)),
                      Text('برنامه‌های انتخاب‌شده مستقیم به اینترنت وصل می‌شوند', style: TextStyle(fontSize: 12, color: Palette.muted)),
                    ]),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(color: Palette.text),
                  decoration: InputDecoration(
                    hintText: 'جستجوی برنامه…',
                    hintStyle: TextStyle(color: Palette.muted),
                    prefixIcon: Icon(Icons.search_rounded, color: Palette.muted),
                    filled: true,
                    fillColor: Palette.fill,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<AppInfo>>(
                  future: _apps,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(child: Text('فهرست برنامه‌ها در دسترس نیست', style: TextStyle(color: Palette.muted)));
                    }
                    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                    final q = _query.trim().toLowerCase();
                    final apps = snap.data!
                        .where((a) => q.isEmpty || a.name.toLowerCase().contains(q) || a.packageName.contains(q))
                        .toList()
                      // Excluded apps first so the current choice is visible at a glance.
                      ..sort((a, b) {
                        final ea = s.excludedApps.contains(a.packageName), eb = s.excludedApps.contains(b.packageName);
                        return ea == eb ? 0 : (ea ? -1 : 1);
                      });
                    return ListenableBuilder(
                      listenable: s,
                      builder: (context, _) => ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: apps.length,
                        itemBuilder: (context, i) {
                          final app = apps[i];
                          final excluded = s.excludedApps.contains(app.packageName);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Glass(
                              radius: 18,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              borderColor: excluded ? Palette.accent : null,
                              onTap: () => s.update((x) {
                                final next = {...x.excludedApps};
                                excluded ? next.remove(app.packageName) : next.add(app.packageName);
                                x.excludedApps = next;
                              }),
                              child: Row(children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: app.icon == null
                                      ? SizedBox.square(dimension: 38, child: Icon(Icons.android_rounded, color: Palette.muted))
                                      : Image.memory(app.icon!, width: 38, height: 38, gaplessPlayback: true),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(app.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Palette.text)),
                                    Text(app.packageName, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr,
                                        style: TextStyle(fontSize: 11, color: Palette.muted)),
                                  ]),
                                ),
                                Checkbox(
                                  value: excluded,
                                  activeColor: const Color(0xFF7C3AED),
                                  onChanged: (_) => s.update((x) {
                                    final next = {...x.excludedApps};
                                    excluded ? next.remove(app.packageName) : next.add(app.packageName);
                                    x.excludedApps = next;
                                  }),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
