import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ProjectWorkflowShortcuts extends StatelessWidget {
  const ProjectWorkflowShortcuts({
    super.key,
    required this.child,
    required this.onToggleOutliers,
    required this.onToggleAllSites,
    required this.onToggleLockAxes,
    required this.onSave,
    required this.onExport,
    required this.onImport,
    required this.onNewSite,
    required this.onUndo,
    required this.onRedo,
    required this.onMarkBad,
  });

  final Widget child;
  final VoidCallback onToggleOutliers;
  final VoidCallback onToggleAllSites;
  final VoidCallback onToggleLockAxes;
  final VoidCallback onSave;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback onNewSite;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onMarkBad;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.keyX): const _MarkBadIntent(),
        LogicalKeySet(LogicalKeyboardKey.keyF): const _ToggleAllSitesIntent(),
        LogicalKeySet(LogicalKeyboardKey.keyO): const _ToggleOutliersIntent(),
        LogicalKeySet(LogicalKeyboardKey.keyL): const _ToggleLockAxesIntent(),
        LogicalKeySet(LogicalKeyboardKey.keyN): const _NewSiteIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS):
            const _SaveIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyE):
            const _ExportIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyI):
            const _ImportIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyZ):
            const _UndoIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.keyZ): const _RedoIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _MarkBadIntent: CallbackAction<_MarkBadIntent>(onInvoke: (_) {
            onMarkBad();
            return null;
          }),
          _ToggleOutliersIntent:
              CallbackAction<_ToggleOutliersIntent>(onInvoke: (_) {
            onToggleOutliers();
            return null;
          }),
          _ToggleAllSitesIntent:
              CallbackAction<_ToggleAllSitesIntent>(onInvoke: (_) {
            onToggleAllSites();
            return null;
          }),
          _ToggleLockAxesIntent:
              CallbackAction<_ToggleLockAxesIntent>(onInvoke: (_) {
            onToggleLockAxes();
            return null;
          }),
          _SaveIntent: CallbackAction<_SaveIntent>(onInvoke: (_) {
            onSave();
            return null;
          }),
          _ExportIntent: CallbackAction<_ExportIntent>(onInvoke: (_) {
            onExport();
            return null;
          }),
          _ImportIntent: CallbackAction<_ImportIntent>(onInvoke: (_) {
            onImport();
            return null;
          }),
          _NewSiteIntent: CallbackAction<_NewSiteIntent>(onInvoke: (_) {
            onNewSite();
            return null;
          }),
          _UndoIntent: CallbackAction<_UndoIntent>(onInvoke: (_) {
            onUndo();
            return null;
          }),
          _RedoIntent: CallbackAction<_RedoIntent>(onInvoke: (_) {
            onRedo();
            return null;
          }),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}

class _MarkBadIntent extends Intent {
  const _MarkBadIntent();
}

class _ToggleOutliersIntent extends Intent {
  const _ToggleOutliersIntent();
}

class _ToggleAllSitesIntent extends Intent {
  const _ToggleAllSitesIntent();
}

class _ToggleLockAxesIntent extends Intent {
  const _ToggleLockAxesIntent();
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}

class _ExportIntent extends Intent {
  const _ExportIntent();
}

class _ImportIntent extends Intent {
  const _ImportIntent();
}

class _NewSiteIntent extends Intent {
  const _NewSiteIntent();
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}
