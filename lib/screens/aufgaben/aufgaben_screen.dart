import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/adaptive_shell.dart';
import '../inventory/shopping_list_screen.dart';
import '../tasks/tasks_screen.dart';

/// Set to 1 before navigating to /aufgaben to pre-select the Einkaufsliste tab.
/// The screen resets this to 0 after consuming it.
final aufgabenInitialTabProvider = StateProvider<int>((ref) => 0);

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
    final initialTab = ref.read(aufgabenInitialTabProvider);
    _tab = TabController(length: _tabs.length, vsync: this, initialIndex: initialTab);
    if (initialTab != 0) {
      Future.microtask(() {
        if (mounted) ref.read(aufgabenInitialTabProvider.notifier).state = 0;
      });
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Listen for external tab switches (e.g. from dashboard while already on screen)
    ref.listen(aufgabenInitialTabProvider, (_, next) {
      if (next != 0 && next != _tab.index) {
        _tab.animateTo(next);
        Future.microtask(() {
          if (mounted) ref.read(aufgabenInitialTabProvider.notifier).state = 0;
        });
      }
    });

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
