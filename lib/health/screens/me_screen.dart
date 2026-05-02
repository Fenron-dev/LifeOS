import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/adaptive_shell.dart';
import 'diary_tab.dart';
import 'measurements_tab.dart';
import 'profile_tab.dart';
import 'weight_tab.dart';

/// "Ich"-Tab — central hub for personal health data.
///
/// Phase 6.1 ships only Gewicht and Profil. Tagebuch, Maße, Fotos, Workouts,
/// Ziele are placeholders that will be filled in subsequent phases (6.2+).
/// They render a "Coming soon"-state instead of a blank screen so the
/// navigation layout is locked in from day one and later phases can land
/// without restructuring the shell.
class MeScreen extends ConsumerStatefulWidget {
  const MeScreen({super.key});

  @override
  ConsumerState<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends ConsumerState<MeScreen>
    with SingleTickerProviderStateMixin {
  static const _tabs = <_MeTabSpec>[
    _MeTabSpec(label: 'Tagebuch', icon: Icons.book_outlined, ready: true),
    _MeTabSpec(label: 'Gewicht', icon: Icons.monitor_weight_outlined, ready: true),
    _MeTabSpec(label: 'Maße', icon: Icons.straighten, ready: true),
    _MeTabSpec(label: 'Fotos', icon: Icons.photo_library_outlined, ready: false),
    _MeTabSpec(label: 'Workouts', icon: Icons.fitness_center, ready: false),
    _MeTabSpec(label: 'Ziele', icon: Icons.flag_outlined, ready: false),
    _MeTabSpec(label: 'Profil', icon: Icons.person_outline, ready: true),
  ];

  late final TabController _controller;

  @override
  void initState() {
    super.initState();
    // Default to "Tagebuch" — the daily diary is the main entry point.
    final initial = _tabs.indexWhere((t) => t.label == 'Tagebuch');
    _controller = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: initial < 0 ? 0 : initial,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ich'),
        actions: shellMenuActions(context),
        bottom: TabBar(
          controller: _controller,
          isScrollable: true,
          tabs: _tabs
              .map((t) => Tab(
                    icon: Icon(t.icon),
                    text: t.label,
                  ))
              .toList(),
        ),
      ),
      body: TabBarView(
        controller: _controller,
        children: _tabs.map((t) {
          if (!t.ready) return _PlaceholderTab(label: t.label, icon: t.icon);
          return switch (t.label) {
            'Tagebuch' => const DiaryTab(),
            'Gewicht' => const WeightTab(),
            'Maße' => const MeasurementsTab(),
            'Profil' => const ProfileTab(),
            _ => _PlaceholderTab(label: t.label, icon: t.icon),
          };
        }).toList(),
      ),
    );
  }
}

class _MeTabSpec {
  final String label;
  final IconData icon;
  final bool ready;
  const _MeTabSpec(
      {required this.label, required this.icon, required this.ready});
}

class _PlaceholderTab extends StatelessWidget {
  final String label;
  final IconData icon;
  const _PlaceholderTab({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: cs.outline),
            const SizedBox(height: 12),
            Text(label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Dieser Bereich folgt in einer späteren Phase.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
