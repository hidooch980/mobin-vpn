import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import 'engine.dart';
import 'vpn_controller.dart';

/// Android home-screen widget + Quick Settings tile: publishes VPN state and handles their toggle taps.
class NativeBridge {
  static const _channel = MethodChannel('mobin/native');
  static const _widget = 'com.mobin.mobin_vpn.MobinWidgetProvider';

  static void attach(VpnController controller) {
    if (!Platform.isAndroid) return;
    HomeWidget.widgetClicked.listen((uri) => _handle(uri, controller));
    HomeWidget.initiallyLaunchedFromHomeWidget().then((uri) => _handle(uri, controller));

    VpnState? lastState;
    String? lastLocation;
    controller.addListener(() {
      final location = _location(controller);
      if (controller.state == lastState && location == lastLocation) return;
      lastState = controller.state;
      lastLocation = location;
      unawaited(_publish(controller));
    });
    unawaited(_publish(controller));
  }

  static Future<void> _handle(Uri? uri, VpnController controller) async {
    if (uri?.host != 'toggle') return;
    await controller.ready.future;
    if (controller.state == VpnState.disconnected || controller.state == VpnState.connected) {
      await controller.toggle();
    }
  }

  static String _location(VpnController c) {
    final current = c.current;
    if (current != null) return current.displayName;
    return switch (c.selectedCountry) {
      null => 'هوشمند',
      VpnController.gamingMode => 'گیمینگ',
      VpnController.favoritesMode => 'علاقه‌مندی‌ها',
      final code => c.countries.where((g) => g.code == code).firstOrNull?.name ?? code,
    };
  }

  static Future<void> _publish(VpnController c) async {
    final connected = c.state == VpnState.connected;
    final status = switch (c.state) {
      VpnState.connected => 'متصل',
      VpnState.connecting => 'در حال اتصال…',
      VpnState.disconnecting => 'در حال قطع…',
      VpnState.disconnected => 'آماده‌ی اتصال',
    };
    try {
      await HomeWidget.saveWidgetData<bool>('connected', connected);
      await HomeWidget.saveWidgetData<String>('status', status);
      await HomeWidget.saveWidgetData<String>('location', _location(c));
      await HomeWidget.updateWidget(qualifiedAndroidName: _widget);
      await _channel.invokeMethod<void>('setVpnState', {'connected': connected});
    } catch (_) {
      // Widget not placed / tile unsupported: nothing to update.
    }
  }
}
