import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simple opt-in screenshot helper for widget tests.
///
/// Set `CAPTURE_SCREENSHOTS=1` in the environment before running
/// `flutter test` to enable writing PNG captures into `buildlogs/`.
class TestScreenshot {
  const TestScreenshot._();

  /// Returns true when the `CAPTURE_SCREENSHOTS` environment flag is enabled.
  static bool get isEnabled =>
      Platform.environment['CAPTURE_SCREENSHOTS'] == '1';

  /// Saves the render output for the widget matched by [finder] into
  /// `buildlogs/[fileName].png`.
  static Future<void> capture(
    WidgetTester tester,
    Finder finder,
    String fileName, {
    double pixelRatio = 2.0,
  }) async {
    if (!isEnabled) return;

    await tester.pumpAndSettle();
    final element = finder.evaluate().singleOrNull;
    if (element == null) {
      return;
    }
    final renderObject = element.renderObject;
    if (renderObject is! RenderRepaintBoundary) {
      return;
    }
    await tester.runAsync(() async {
      final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return;
      }

      final outputDir = Directory('buildlogs');
      if (!outputDir.existsSync()) {
        outputDir.createSync(recursive: true);
      }

      final file = File('${outputDir.path}/$fileName');
      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      await file.writeAsBytes(bytes, flush: true);
      // Provide a quiet breadcrumb for the CLI without failing tests when absent.
      // ignore: avoid_print
      print('Saved screenshot to ${file.path}');
    });
  }
}
