import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/adaptive_shell.dart';
import '../inventory/shopping_list_screen.dart';
import '../tasks/tasks_screen.dart';

class AufgabenScreen extends ConsumerStatefulWidget {
  const AufgabenScreen({super.key});

  @override
  ConsumerState<AufgabenScreen> createState() => _AufgabenScreenState();
}

class _AufgabenScreenState extends ConsumerState<AufgabenScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  static const _tabs = [
    (label: 'Aufgaben', icon: Icons.task_outlined),
    (label: 'Einkaufsliste', icon: Icons.shopping_cart_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aufgaben'),
        actions: shellMenuActions(context),
        bottom: TabBar(
          controller: _tab,
          tabs: _tabs
              .map((t) => Tab(icon: Icon(t.icon), text: t.label))
              .toList(),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          TasksScreen(embedded: true),
          ShoppingListScreen(embedded: true),
        ],
      ),
    );
  }
}
