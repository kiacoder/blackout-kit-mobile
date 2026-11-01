import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

/// Raw C-ABI Struct for Engine Stats
final class BlackoutStatsNative extends ffi.Struct {
  @ffi.Uint64()
  external int txBytes;

  @ffi.Uint64()
  external int rxBytes;

  @ffi.Uint64()
  external int txPackets;

  @ffi.Uint64()
  external int rxPackets;

  @ffi.Uint32()
  external int activeConnections;
}

// C-ABI Function Signatures
typedef _c_blackout_init = ffi.Int32 Function(ffi.Int32 logLevel);
typedef _dart_blackout_init = int Function(int logLevel);

typedef _c_blackout_start = ffi.Int32 Function(ffi.Int32 tunFd, ffi.Pointer<Utf8> configJson);
typedef _dart_blackout_start = int Function(int tunFd, ffi.Pointer<Utf8> configJson);

typedef _c_blackout_stop = ffi.Int32 Function();
typedef _dart_blackout_stop = int Function();

typedef _c_blackout_is_running = ffi.Bool Function();
typedef _dart_blackout_is_running = bool Function();

typedef _c_blackout_version = ffi.Pointer<Utf8> Function();
typedef _dart_blackout_version = ffi.Pointer<Utf8> Function();

typedef _c_blackout_get_last_error = ffi.Int32 Function(ffi.Pointer<Utf8> buffer, ffi.Int32 maxLen);
typedef _dart_blackout_get_last_error = int Function(ffi.Pointer<Utf8> buffer, int maxLen);

/// High-level Dart interface to the native in-house Rust core
class BlackoutCoreBindings {
  static final BlackoutCoreBindings _instance = BlackoutCoreBindings._internal();
  factory BlackoutCoreBindings() => _instance;

  ffi.DynamicLibrary? _lib;
  bool _available = false;

  _dart_blackout_init? _init;
  _dart_blackout_start? _start;
  _dart_blackout_stop? _stop;
  _dart_blackout_is_running? _isRunning;
  _dart_blackout_version? _version;
  _dart_blackout_get_last_error? _getLastError;

  BlackoutCoreBindings._internal() {
    _loadLibrary();
  }

  bool get isAvailable => _available;

  void _loadLibrary() {
    try {
      if (Platform.isAndroid) {
        _lib = ffi.DynamicLibrary.open('libblackout_core.so');
      } else if (Platform.isIOS) {
        _lib = ffi.DynamicLibrary.process();
      }
      if (_lib != null) {
        _init = _lib!.lookupFunction<_c_blackout_init, _dart_blackout_init>('blackout_init');
        _start = _lib!.lookupFunction<_c_blackout_start, _dart_blackout_start>('blackout_start');
        _stop = _lib!.lookupFunction<_c_blackout_stop, _dart_blackout_stop>('blackout_stop');
        _isRunning = _lib!.lookupFunction<_c_blackout_is_running, _dart_blackout_is_running>('blackout_is_running');
        _version = _lib!.lookupFunction<_c_blackout_version, _dart_blackout_version>('blackout_version');
        _getLastError = _lib!.lookupFunction<_c_blackout_get_last_error, _dart_blackout_get_last_error>('blackout_get_last_error');
        _available = true;
      }
    } catch (_) {
      // Dynamic library not yet loaded or running in pure test environment
      _available = false;
    }
  }

  int init({int logLevel = 2}) {
    if (!_available || _init == null) return -99;
    return _init!(logLevel);
  }

  int start(int tunFd, String configJson) {
    if (!_available || _start == null) return -99;
    final ptr = configJson.toNativeUtf8();
    try {
      return _start!(tunFd, ptr);
    } finally {
      calloc.free(ptr);
    }
  }

  int stop() {
    if (!_available || _stop == null) return 0;
    return _stop!();
  }

  bool isRunning() {
    if (!_available || _isRunning == null) return false;
    return _isRunning!();
  }

  String getVersion() {
    if (!_available || _version == null) return 'unloaded';
    return _version!().toDartString();
  }

  String getLastError() {
    if (!_available || _getLastError == null) return 'Library not available';
    final ptr = calloc<ffi.Uint8>(512).cast<Utf8>();
    try {
      _getLastError!(ptr, 512);
      return ptr.toDartString();
    } finally {
      calloc.free(ptr);
    }
  }
}
