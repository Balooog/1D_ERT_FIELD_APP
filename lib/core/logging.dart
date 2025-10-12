import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Simple structured logging helper that prefixes category/level metadata and
/// mirrors the output to a runtime log file.
class LogHarness {
  LogHarness._();

  static final LogHarness instance = LogHarness._();

  IOSink? _sink;
  String? _sessionFileName;
  bool _initializing = false;

  Future<void> ensureInitialized() async {
    if (kIsWeb) {
      return;
    }
    if (_sink != null || _initializing) {
      while (_initializing && _sink == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return;
    }
    _initializing = true;
    try {
      final directory = Directory('buildlogs');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${directory.path}/runtime_$timestamp.log');
      _sink = file.openWrite(mode: FileMode.writeOnlyAppend);
      _sessionFileName = file.path;
      _sink!.writeln(
        '--- ResiCheck runtime session started ${DateTime.now().toIso8601String()} ---',
      );
    } finally {
      _initializing = false;
    }
  }

  void i(String category, String message) {
    _write('INFO', category, message);
  }

  void w(String category, String message) {
    _write('WARN', category, message);
  }

  void e(String category, String message,
      [Object? error, StackTrace? stackTrace]) {
    final buffer = StringBuffer(message);
    if (error != null) {
      buffer
        ..writeln()
        ..write('Error: $error');
    }
    if (stackTrace != null) {
      buffer
        ..writeln()
        ..write(stackTrace);
    }
    _write('ERROR', category, buffer.toString());
  }

  void _write(String level, String category, String message) {
    final timestamp = DateTime.now().toIso8601String();
    final normalizedCategory =
        category.trim().isEmpty ? 'App' : category.trim();
    final normalizedMessage = message.trim();
    final line = '[$timestamp][$level][$normalizedCategory] $normalizedMessage';
    debugPrint(line);
    _sink?.writeln(line);
  }

  Future<void> dispose() async {
    final sink = _sink;
    if (sink != null) {
      await sink.flush();
      await sink.close();
    }
    _sink = null;
    _sessionFileName = null;
  }

  String? get sessionFile => _sessionFileName;
}

/// Convenient top-level logger reference.
final LOG = LogHarness.instance;
