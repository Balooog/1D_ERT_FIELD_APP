import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

typedef LogLevel = String;

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  Directory? _directory;
  File? _jsonl;
  File? _txt;
  bool _initialized = false;

  Future<void> init({String subdir = 'logs/dev'}) async {
    if (_initialized || kIsWeb) {
      return;
    }
    final basePath = Directory.current.path;
    final directory = Directory('$basePath/$subdir');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final textFile = File('${directory.path}/session_$timestamp.txt');
    final jsonFile = File('${directory.path}/session_$timestamp.jsonl');
    await textFile.writeAsString('[session] $timestamp\n',
        mode: FileMode.writeOnly);
    _directory = directory;
    _txt = textFile;
    _jsonl = jsonFile;
    _initialized = true;
  }

  void log(
    LogLevel level,
    String event, {
    String? message,
    Map<String, Object?> extra = const {},
    Object? error,
    StackTrace? stackTrace,
  }) {
    final record = <String, Object?>{
      'ts': DateTime.now().toIso8601String(),
      'level': level,
      'event': event,
    };
    if (message != null && message.isNotEmpty) {
      record['message'] = message;
    }
    final payload = _normalizeExtras(extra);
    if (payload.isNotEmpty) {
      record['extra'] = payload;
    }
    if (error != null) {
      record['error'] = error.toString();
    }
    if (stackTrace != null) {
      record['stack'] = stackTrace.toString();
    }
    final buffer = StringBuffer('[$level] $event');
    if (message != null && message.isNotEmpty) {
      buffer.write(' $message');
    }
    if (payload.isNotEmpty) {
      buffer.write(' ${jsonEncode(payload)}');
    }
    _writeLine(buffer.toString());
    _appendJson(record);
  }

  void info(String event, {Map<String, Object?> extra = const {}}) =>
      log('INFO', event, extra: extra);

  void warn(String event, {Map<String, Object?> extra = const {}}) =>
      log('WARN', event, extra: extra);

  void error(
    String event, {
    Map<String, Object?> extra = const {},
    Object? error,
    StackTrace? stackTrace,
  }) =>
      log(
        'ERROR',
        event,
        extra: extra,
        error: error,
        stackTrace: stackTrace,
      );

  // Backwards compatibility with previous logging helper.
  void i(String category, String message,
          {Map<String, Object?> extra = const {}}) =>
      log('INFO', category, message: message, extra: extra);

  void w(String category, String message,
          {Map<String, Object?> extra = const {}}) =>
      log('WARN', category, message: message, extra: extra);

  void e(
    String category,
    String message, [
    Object? error,
    StackTrace? stackTrace,
  ]) =>
      log(
        'ERROR',
        category,
        message: message,
        error: error,
        stackTrace: stackTrace,
      );

  void _appendJson(Map<String, Object?> record) {
    final jsonFile = _jsonl;
    if (jsonFile == null) {
      return;
    }
    try {
      jsonFile.writeAsStringSync('${jsonEncode(record)}\n',
          mode: FileMode.append);
    } catch (_) {
      // Ignore JSON write failures; console output already captured.
    }
  }

  void _writeLine(String text) {
    final line = text.trimRight();
    // ignore: avoid_print
    print(line);
    final textFile = _txt;
    if (textFile == null) {
      return;
    }
    try {
      textFile.writeAsStringSync('$line\n', mode: FileMode.append);
    } catch (_) {
      // Ignore disk write failures.
    }
  }

  Map<String, Object?> _normalizeExtras(Map<String, Object?> extra) {
    if (extra.isEmpty) {
      return const {};
    }
    final sanitized = <String, Object?>{};
    extra.forEach((key, value) {
      if (value == null) {
        return;
      }
      sanitized[key] = value;
    });
    return sanitized;
  }

  Directory? get directory => _directory;
}

/// Convenient top-level logger reference.
// ignore: non_constant_identifier_names
final AppLogger LOG = AppLogger.instance;
