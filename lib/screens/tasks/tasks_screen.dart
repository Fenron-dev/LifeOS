import 'package:flutter/material.dart';

import '../../widgets/adaptive_shell.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aufgaben'),
        actions: shellMenuActions(context),
      ),
      body: const Center(child: Text('Aufgaben – Phase 3')),
    );
  }
}
