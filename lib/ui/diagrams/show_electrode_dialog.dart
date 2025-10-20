import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'electrode_diagram.dart';

typedef DiagramExportDirectoryBuilder = Future<Directory> Function();

Future<void> showElectrodeDiagramDialog({
  required BuildContext context,
  required String projectName,
  required String siteName,
  required double aFt,
  required double pinInFt,
  required double pinOutFt,
  DiagramExportDirectoryBuilder? exportDirectoryBuilder,
}) async {
  final repaintKey = GlobalKey();
  final messenger = ScaffoldMessenger.maybeOf(context);

  Future<File?> savePng() async {
    try {
      final boundary = repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        return null;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        return null;
      }

      Directory targetDir;
      if (exportDirectoryBuilder != null) {
        targetDir = await exportDirectoryBuilder();
      } else {
        targetDir = await getTemporaryDirectory();
      }
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      final safeProject = projectName.replaceAll(RegExp(r'[^\w\.-]+'), '_');
      final safeSite = siteName.replaceAll(RegExp(r'[^\w\.-]+'), '_');
      final fileName =
          '${safeProject}_${safeSite}_a-${aFt.toStringAsFixed(2)}ft.png';
      final file = File(p.join(targetDir.path, fileName));
      await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      content: RepaintBoundary(
        key: repaintKey,
        child: SizedBox(
          width: 600,
          height: 180,
          child: CustomPaint(
            painter: ElectrodeDiagramPainter(
              aFt: aFt,
              pinInFt: pinInFt,
              pinOutFt: pinOutFt,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final file = await savePng();
            if (!dialogContext.mounted) {
              return;
            }
            if (file == null) {
              if (messenger != null) {
                messenger.showSnackBar(
                  const SnackBar(content: Text('Diagram save failed')),
                );
              }
              return;
            }
            if (messenger != null) {
              messenger.showSnackBar(
                SnackBar(content: Text('Saved diagram to ${file.path}')),
              );
            }
          },
          child: const Text('Save PNG'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
