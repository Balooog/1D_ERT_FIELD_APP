import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

enum ScreenshotRegion {
  workspace,
  plotsPanel,
  tablePanel,
  siteList,
  rightRail;

  String get filePrefix => switch (this) {
        ScreenshotRegion.workspace => 'workspace',
        ScreenshotRegion.plotsPanel => 'plots',
        ScreenshotRegion.tablePanel => 'table',
        ScreenshotRegion.siteList => 'site_list',
        ScreenshotRegion.rightRail => 'right_rail',
      };
}

class ScreenshotCaptureResult {
  ScreenshotCaptureResult._(this.path, this.error, this.stackTrace);

  factory ScreenshotCaptureResult.success(String path) =>
      ScreenshotCaptureResult._(path, null, null);

  factory ScreenshotCaptureResult.failure(
    Object error,
    StackTrace stackTrace,
  ) =>
      ScreenshotCaptureResult._(null, error, stackTrace);

  final String? path;
  final Object? error;
  final StackTrace? stackTrace;

  bool get isSuccess => path != null && error == null;
}

class ScreenshotRegionController {
  ScreenshotRegionController() : boundaryKey = GlobalKey();

  final GlobalKey boundaryKey;

  RenderRepaintBoundary? get boundary {
    final context = boundaryKey.currentContext;
    if (context == null) {
      return null;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is RenderRepaintBoundary) {
      return renderObject;
    }
    return null;
  }
}

class ScreenshotService {
  ScreenshotService._();

  static final ScreenshotService _instance = ScreenshotService._();

  factory ScreenshotService() => _instance;

  final Map<ScreenshotRegion, ScreenshotRegionController> _controllers = {};

  ScreenshotRegionController controllerForRegion(ScreenshotRegion region) {
    return _controllers.putIfAbsent(
      region,
      ScreenshotRegionController.new,
    );
  }

  Widget wrapRegion({
    required ScreenshotRegion region,
    required Widget child,
  }) {
    final controller = controllerForRegion(region);
    return RepaintBoundary(
      key: controller.boundaryKey,
      child: child,
    );
  }

  Future<ScreenshotCaptureResult> captureRegion({
    required ScreenshotRegion region,
    Directory? projectDirectory,
    String? prefixOverride,
  }) async {
    final controller = controllerForRegion(region);
    final boundary = controller.boundary;
    if (boundary == null) {
      return ScreenshotCaptureResult.failure(
        StateError('No repaint boundary registered for $region'),
        StackTrace.current,
      );
    }

    if (boundary.debugNeedsPaint) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      try {
        await WidgetsBinding.instance.endOfFrame;
      } catch (_) {
        // Ignore if binding is unavailable (e.g. tests tearing down).
      }
    }

    try {
      final directory = _resolveCaptureDirectory(projectDirectory);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final prefix = _sanitizeFileSegment(prefixOverride ?? region.filePrefix);
      final timestamp =
          DateTime.now().toIso8601String().replaceAll(':', '-'); // safe name
      final fileName = '${prefix}_$timestamp.png';

      final image = await boundary.toImage(pixelRatio: _devicePixelRatio());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return ScreenshotCaptureResult.failure(
          StateError('Failed to encode screenshot bytes'),
          StackTrace.current,
        );
      }

      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      final file = File(p.join(directory.path, fileName));
      await file.writeAsBytes(bytes, flush: true);
      return ScreenshotCaptureResult.success(file.path);
    } on Object catch (error, stackTrace) {
      return ScreenshotCaptureResult.failure(error, stackTrace);
    }
  }

  double _devicePixelRatio() {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final implicitView = dispatcher.implicitView;
    if (implicitView != null) {
      return implicitView.devicePixelRatio;
    }
    final views = dispatcher.views;
    if (views.isNotEmpty) {
      return views.first.devicePixelRatio;
    }
    return 1.0;
  }

  Directory _resolveCaptureDirectory(Directory? projectDirectory) {
    if (projectDirectory != null) {
      return Directory(p.join(projectDirectory.path, 'exports', 'screenshots'));
    }
    return Directory(p.join('buildlogs', 'screens'));
  }

  String _sanitizeFileSegment(String value) {
    final normalized = value.trim().toLowerCase();
    final replaced = normalized.replaceAll(RegExp(r'[^a-z0-9\-_]+'), '_');
    final collapsed = replaced.replaceAll(RegExp(r'_{2,}'), '_');
    final trimmed = collapsed.replaceAll(RegExp(r'^_|_$'), '');
    return trimmed.isEmpty ? 'capture' : trimmed;
  }
}
