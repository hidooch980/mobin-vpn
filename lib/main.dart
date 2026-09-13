import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'core/native_bridge.dart';
import 'core/vpn_controller.dart';
import 'ui/home_screen.dart';
import 'ui/style.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = VpnController();
  runApp(MobinApp(controller: controller));
  NativeBridge.attach(controller);
  unawaited(controller.init());
}

class MobinApp extends StatefulWidget {
  const MobinApp({super.key, required this.controller});

  final VpnController controller;

  @override
  State<MobinApp> createState() => _MobinAppState();
}

class _MobinAppState extends State<MobinApp> {
  // Closing the window must turn the Windows system proxy off again.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onExitRequested: () async {
      await widget.controller.disconnect();
      return AppExitResponse.exit;
    },
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobin VPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF7C3AED),
        scaffoldBackgroundColor: Palette.bg,
        fontFamily: Platform.isWindows ? 'Segoe UI' : null,
      ),
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: HomeScreen(controller: widget.controller),
    );
  }
}
