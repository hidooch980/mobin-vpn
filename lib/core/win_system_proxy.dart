import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Sets the per-user Windows proxy (what browsers and most apps use) and tells WinINet to reload it.
class WinSystemProxy {
  static const _hkcu = -2147483647; // HKEY_CURRENT_USER, sign-extended
  static const _regSz = 1, _regDword = 4;
  static const _settingsKey = r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  static final _regSetKeyValue = DynamicLibrary.open('advapi32.dll').lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Void>, Uint32),
      int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Void>, int)>('RegSetKeyValueW');

  static final _internetSetOption = DynamicLibrary.open('wininet.dll').lookupFunction<
      Int32 Function(Pointer<Void>, Uint32, Pointer<Void>, Uint32),
      int Function(Pointer<Void>, int, Pointer<Void>, int)>('InternetSetOptionW');

  static void enable(String hostPort) {
    _setString('ProxyServer', hostPort);
    _setString('ProxyOverride', 'localhost;127.*;10.*;172.16.*;192.168.*;<local>');
    _setDword('ProxyEnable', 1);
    _refresh();
  }

  static void disable() {
    _setDword('ProxyEnable', 0);
    _refresh();
  }

  static void _setDword(String name, int value) {
    final data = calloc<Uint32>()..value = value;
    _write(name, _regDword, data.cast(), sizeOf<Uint32>());
    calloc.free(data);
  }

  static void _setString(String name, String value) {
    final data = value.toNativeUtf16();
    _write(name, _regSz, data.cast(), (value.length + 1) * 2);
    calloc.free(data);
  }

  static void _write(String name, int type, Pointer<Void> data, int size) {
    final key = _settingsKey.toNativeUtf16();
    final valueName = name.toNativeUtf16();
    _regSetKeyValue(_hkcu, key, valueName, type, data, size);
    calloc.free(key);
    calloc.free(valueName);
  }

  static void _refresh() {
    const settingsChanged = 39, refresh = 37;
    _internetSetOption(nullptr, settingsChanged, nullptr, 0);
    _internetSetOption(nullptr, refresh, nullptr, 0);
  }
}
