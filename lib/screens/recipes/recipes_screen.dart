import 'package:flutter/material.dart';

import '../../widgets/adaptive_shell.dart';

class RecipesScreen extends StatelessWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rezepte'),
        actions: shellMenuActions(context),
      ),
      body: const Center(child: Text('Rezepte – Phase 3')),
    );
  }
}
