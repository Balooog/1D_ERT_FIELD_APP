import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/logging_service.dart';
import 'ui/project_workflow/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LoggingService.instance.ensureInitialized();
  LoggingService.instance.log('Launching ResiCheck UI');
  runApp(const ProviderScope(child: ResiCheckApp()));
}

class ResiCheckApp extends StatelessWidget {
  const ResiCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ResiCheck',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ProjectWorkflowHomePage(),
    );
  }
}
