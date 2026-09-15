import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../core/amnezia.dart';
import '../core/app_log.dart';
import '../core/settings.dart';
import 'strings.dart';
import 'style.dart';

/// "وارد کردن کانفیگ Amnezia": paste the text or pick a .conf file; validated and stored only in local
/// settings (it contains the private key). Returns true when a config was saved.
Future<bool> showAmneziaImport(BuildContext context, AppSettings settings) async =>
    await showDialog<bool>(context: context, builder: (_) => _AmneziaImportDialog(settings: settings)) ?? false;

class _AmneziaImportDialog extends StatefulWidget {
  const _AmneziaImportDialog({required this.settings});

  final AppSettings settings;

  @override
  State<_AmneziaImportDialog> createState() => _AmneziaImportDialogState();
}

class _AmneziaImportDialogState extends State<_AmneziaImportDialog> {
  final _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final file = await openFile(acceptedTypeGroups: const [
        XTypeGroup(label: 'AmneziaWG', extensions: ['conf', 'txt']),
      ]);
      if (file == null) return;
      final content = await file.readAsString();
      if (!mounted) return;
      setState(() {
        _text.text = content;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = tr('خواندن فایل ممکن نشد', 'Could not read the file'));
    }
  }

  Future<void> _save() async {
    AmneziaConfig? config;
    String? problem;
    try {
      config = AmneziaConfig.parse(_text.text);
    } on FormatException catch (e) {
      problem = e.message;
    }
    if (config == null) {
      setState(() => _error = problem ?? tr('کانفیگ نامعتبر است', 'Invalid config'));
      return;
    }
    final json = jsonEncode(config.toJson());
    AppLog.add('amnezia: config imported (${config.endpoints.length} endpoint(s), junk ${config.hasJunk ? 'on' : 'off'})');
    await widget.settings.update((x) => x
      ..amneziaConfig = json
      ..amneziaEndpoint = '');
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: L10n.direction,
      child: AlertDialog(
        backgroundColor: Palette.sheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Palette.cardRadius)),
        title: Text(tr('وارد کردن کانفیگ Amnezia', 'Import Amnezia config'),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Palette.text)),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  tr('متن کانفیگ AmneziaWG را بچسبانید یا فایل conf را انتخاب کنید. کلید خصوصی فقط روی همین دستگاه ذخیره می‌شود.',
                      'Paste the AmneziaWG config or choose its .conf file. The private key is stored only on this device.'),
                  style: TextStyle(fontSize: 12, color: Palette.muted),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _text,
                  minLines: 6,
                  maxLines: 10,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: Palette.text, fontSize: 12, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Palette.raised,
                    hintText: '[Interface]\nPrivateKey = …\n\n[Peer]\nEndpoint = …',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Palette.pillRadius), borderSide: BorderSide.none),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
                ],
                const SizedBox(height: 8),
                Text(
                  tr('خروجی WARP ممکن است ایران باشد؛ در این صورت بعضی سرویس‌ها کار نمی‌کنند.',
                      'WARP may exit in Iran; some services will not work then.'),
                  style: TextStyle(fontSize: 11, color: Palette.muted),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _pickFile, child: Text(tr('انتخاب فایل', 'Choose file'))),
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('انصراف', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Palette.accent,
              foregroundColor: Palette.bg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Palette.pillRadius)),
            ),
            onPressed: _save,
            child: Text(tr('ذخیره', 'Save')),
          ),
        ],
      ),
    );
  }
}
