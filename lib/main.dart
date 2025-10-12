import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/hydration_gate.dart';
import 'core/logging.dart';
import 'services/logging_service.dart';
import 'services/storage_service.dart';
import 'ui/project_workflow/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.black,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                'UI render error:\n\n${details.exceptionAsString()}',
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ),
        ),
      ),
    );
  };
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };
  await LoggingService.instance.ensureInitialized();
  LOG.i('Bootstrap', 'Launching ResiCheck UI');
  runApp(const ProviderScope(child: ResiCheckApp()));
}

class ResiCheckApp extends StatefulWidget {
  const ResiCheckApp({super.key, this.storage});

  final ProjectStorageService? storage;

  @override
  State<ResiCheckApp> createState() => _ResiCheckAppState();
}

class _ResiCheckAppState extends State<ResiCheckApp> {
  late final HydrationGate _hydrationGate;
  late final ProjectStorageService _storage;

  @override
  void initState() {
    super.initState();
    _hydrationGate = HydrationGate();
    _storage = widget.storage ?? ProjectStorageService();
  }

  @override
  void dispose() {
    _hydrationGate.dispose();
    super.dispose();
  }

  Future<void> _warmUp() async {
    LOG.i('Hydration', 'Ensuring sample project assets');
    await _storage.ensureSampleProject();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ResiCheck',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: HydrationGateBuilder(
        gate: _hydrationGate,
        onWarmUp: _warmUp,
        loadingBuilder: (context) => const _HydrationScaffold(
          message: 'Preparing project workspace…',
          child: CircularProgressIndicator(),
        ),
        errorBuilder: (context, error, stack) => _HydrationScaffold(
          message: 'Startup failed',
          child: Text(error.toString()),
        ),
        readyBuilder: (context) => ProjectWorkflowHomePage(storage: _storage),
      ),
    );
  }
}

class _HydrationScaffold extends StatelessWidget {
  const _HydrationScaffold({
    required this.child,
    this.message,
  });

  final Widget child;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            if (message != null) ...[
              const SizedBox(height: 12),
              Text(
                message!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
