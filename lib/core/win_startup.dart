import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Start with Windows via HKCU\...\Run (per user, no admin needed).
class WinStartup {
  static const _hkcu = -2147483647; // HKEY_CURRENT_USER, sign-extended
  static const _regSz = 1, _rrfRtRegSz = 0x00000002;
  static const _runKey = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const _valueName = 'MobinVPN';
  static const autostartArg = '--autostart';

  static final _advapi = DynamicLibrary.open('advapi32.dll');
  static final _regSetKeyValue = _advapi.lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Void>, Uint32),
      int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Void>, int)>('RegSetKeyValueW');
  static final _regDeleteKeyValue = _advapi.lookupFunction<Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>),
      int Function(int, Pointer<Utf16>, Pointer<Utf16>)>('RegDeleteKeyValueW');
  static final _regGetValue = _advapi.lookupFunction<
      Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32, Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>),
      int Function(int, Pointer<Utf16>, Pointer<Utf16>, int, Pointer<Uint32>, Pointer<Void>, Pointer<Uint32>)>('RegGetValueW');

  static String get _command => '"${Platform.resolvedExecutable}" $autostartArg';

  static bool get isEnabled => using((arena) {
        final size = arena<Uint32>();
        final result = _regGetValue(_hkcu, _runKey.toNativeUtf16(allocator: arena), _valueName.toNativeUtf16(allocator: arena),
            _rrfRtRegSz, nullptr, nullptr, size);
        return result == 0;
      });

  static void setEnabled(bool enabled) => using((arena) {
        final key = _runKey.toNativeUtf16(allocator: arena);
        final name = _valueName.toNativeUtf16(allocator: arena);
        if (enabled) {
          final value = _command.toNativeUtf16(allocator: arena);
          _regSetKeyValue(_hkcu, key, name, _regSz, value.cast(), (_command.length + 1) * 2);
        } else {
          _regDeleteKeyValue(_hkcu, key, name);
        }
      });
}
