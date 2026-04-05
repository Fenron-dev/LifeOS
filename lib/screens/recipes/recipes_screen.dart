import 'package:flutter/material.dart';

class RecipesScreen extends StatelessWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rezepte')),
      body: const Center(child: Text('Rezepte – Phase 3')),
    );
  }
}
