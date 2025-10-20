import 'dart:io';
import '../core/logging.dart';

Future<bool> tryOpenFile(String path) async {
  if (path.isEmpty) {
    return false;
  }
  final file = File(path);
  if (!await file.exists()) {
    LOG.warn(
      'file_open_skipped',
      extra: {'path': path, 'reason': 'missing'},
    );
    return false;
  }
  try {
    ProcessResult result;
    if (Platform.isMacOS) {
      result = await Process.run('open', [file.path]);
    } else if (Platform.isWindows) {
      result = await Process.run('cmd', ['/c', 'start', '', file.path]);
    } else if (Platform.isLinux) {
      result = await Process.run('xdg-open', [file.path]);
    } else {
      LOG.warn(
        'file_open_unsupported_platform',
        extra: {'path': path, 'platform': Platform.operatingSystem},
      );
      return false;
    }
    if (result.exitCode != 0) {
      LOG.warn(
        'file_open_nonzero_exit',
        extra: {'path': path, 'exitCode': result.exitCode},
      );
      return false;
    }
    return true;
  } catch (error, stackTrace) {
    LOG.error(
      'file_open_failed',
      extra: {'path': path},
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  }
}
