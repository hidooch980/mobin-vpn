import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';

import '../core/app_log.dart';
import 'strings.dart';
import 'widgets.dart';

const telegramHandle = '@Molido_Vpn';
const telegramUrl = 'https://t.me/Molido_Vpn';

/// Opens [url] in the system browser / handler app (no url_launcher dependency).
Future<void> openLink(String url) async {
  try {
    if (Platform.isWindows) {
      await Process.start('explorer', [url], mode: ProcessStartMode.detached);
    } else if (Platform.isAndroid) {
      await AndroidIntent(action: 'action_view', data: url).launch();
    }
  } catch (e) {
    AppLog.add('open link failed: $e');
  }
}

/// Compact "Telegram support" row, used on the home screen and in Settings → About.
class TelegramSupportRow extends StatelessWidget {
  const TelegramSupportRow({super.key});

  @override
  Widget build(BuildContext context) => NavSettingRow(
        icon: Icons.send_rounded,
        title: tr('پشتیبانی تلگرام', 'Telegram support'),
        value: telegramHandle,
        ltrValue: true,
        onTap: () => openLink(telegramUrl),
      );
}
