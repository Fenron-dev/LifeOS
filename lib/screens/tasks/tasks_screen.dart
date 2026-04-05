import 'package:flutter/material.dart';

class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aufgaben')),
      body: const Center(child: Text('Aufgaben – Phase 1')),
    );
  }
}
