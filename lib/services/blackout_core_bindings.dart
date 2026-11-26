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
typedef _CBlackoutInit = ffi.Int32 Function(ffi.Int32 logLevel);
typedef _DartBlackoutInit = int Function(int logLevel);

typedef _CBlackoutStart = ffi.Int32 Function(ffi.Int32 tunFd, ffi.Pointer<Utf8> configJson);
typedef _DartBlackoutStart = int Function(int tunFd, ffi.Pointer<Utf8> configJson);

typedef _CBlackoutStop = ffi.Int32 Function();
typedef _DartBlackoutStop = int Function();

typedef _CBlackoutIsRunning = ffi.Bool Function();
typedef _DartBlackoutIsRunning = bool Function();

typedef _CBlackoutVersion = ffi.Pointer<Utf8> Function();
typedef _DartBlackoutVersion = ffi.Pointer<Utf8> Function();

typedef _CBlackoutGetLastError = ffi.Int32 Function(ffi.Pointer<Utf8> buffer, ffi.Int32 maxLen);
typedef _DartBlackoutGetLastError = int Function(ffi.Pointer<Utf8> buffer, int maxLen);

/// High-level Dart interface to the native in-house Rust core
class BlackoutCoreBindings {
  static final BlackoutCoreBindings _instance = BlackoutCoreBindings._internal();
  factory BlackoutCoreBindings() => _instance;

  ffi.DynamicLibrary? _lib;
  bool _available = false;

  _DartBlackoutInit? _init;
  _DartBlackoutStart? _start;
  _DartBlackoutStop? _stop;
  _DartBlackoutIsRunning? _isRunning;
  _DartBlackoutVersion? _version;
  _DartBlackoutGetLastError? _getLastError;

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
        _init = _lib!.lookupFunction<_CBlackoutInit, _DartBlackoutInit>('blackout_init');
        _start = _lib!.lookupFunction<_CBlackoutStart, _DartBlackoutStart>('blackout_start');
        _stop = _lib!.lookupFunction<_CBlackoutStop, _DartBlackoutStop>('blackout_stop');
        _isRunning = _lib!.lookupFunction<_CBlackoutIsRunning, _DartBlackoutIsRunning>('blackout_is_running');
        _version = _lib!.lookupFunction<_CBlackoutVersion, _DartBlackoutVersion>('blackout_version');
        _getLastError = _lib!.lookupFunction<_CBlackoutGetLastError, _DartBlackoutGetLastError>('blackout_get_last_error');
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
