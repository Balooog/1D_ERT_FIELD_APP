import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

class LoggingService {
  LoggingService._();

  static final LoggingService instance = LoggingService._();

  IOSink? _sink;
  bool _initialized = false;
  void Function(String? message, {int? wrapWidth})? _previousDebugPrint;
  FlutterExceptionHandler? _previousFlutterError;

  Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }

    _previousDebugPrint = debugPrint;

    if (kIsWeb) {
      _initialized = true;
      return;
    }

    final directory = Directory('buildlogs');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${directory.path}/runtime_$timestamp.log');
    _sink = file.openWrite(mode: FileMode.writeOnlyAppend);
    _sink?.writeln(
        '--- ResiCheck runtime session started ${DateTime.now().toIso8601String()} ---');

    final previousDebugPrint = _previousDebugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      final text = message ?? '';
      final now = DateTime.now().toIso8601String();
      _sink?.writeln('[$now] $text');
      _sink?.flush();
      previousDebugPrint?.call(message, wrapWidth: wrapWidth);
    };

    _previousFlutterError = FlutterError.onError;
    final previousFlutterError = _previousFlutterError;
    FlutterError.onError = (FlutterErrorDetails details) {
      final buffer =
          StringBuffer('FlutterError: ${details.exceptionAsString()}');
      if (details.stack != null) {
        buffer
          ..writeln()
          ..write(details.stack);
      }
      log(buffer.toString());
      previousFlutterError?.call(details);
    };

    _initialized = true;
  }

  void log(String message) {
    if (!_initialized || _sink == null) {
      _previousDebugPrint?.call(message);
      return;
    }

    final now = DateTime.now().toIso8601String();
    _sink?.writeln('[$now] $message');
    _sink?.flush();
    _previousDebugPrint?.call(message);
  }

  Future<void> dispose() async {
    if (_previousDebugPrint != null) {
      debugPrint = _previousDebugPrint!;
    }
    FlutterError.onError = _previousFlutterError;
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    _initialized = false;
    _previousDebugPrint = null;
    _previousFlutterError = null;
  }
}
