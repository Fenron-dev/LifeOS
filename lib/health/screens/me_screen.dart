import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../widgets/adaptive_shell.dart';
import '../services/app_lock_service.dart';
import 'diary_tab.dart';
import 'goals_tab.dart';
import 'measurements_tab.dart';
import 'photos_tab.dart';
import 'profile_tab.dart';
import 'weight_tab.dart';
import 'workouts_tab.dart';

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _tabs = <_MeTabSpec>[
    _MeTabSpec(label: 'Tagebuch', icon: Icons.book_outlined, ready: true),
    _MeTabSpec(label: 'Gewicht', icon: Icons.monitor_weight_outlined, ready: true),
    _MeTabSpec(label: 'Maße', icon: Icons.straighten, ready: true),
    _MeTabSpec(label: 'Fotos', icon: Icons.photo_library_outlined, ready: true),
    _MeTabSpec(label: 'Workouts', icon: Icons.fitness_center, ready: true),
    _MeTabSpec(label: 'Ziele', icon: Icons.flag_outlined, ready: true),
    _MeTabSpec(label: 'Profil', icon: Icons.person_outline, ready: true),
  ];

  late final TabController _controller;

  /// Whether the Fotos tab has been unlocked this session.
  bool _photosUnlocked = false;
  DateTime? _lastActiveTime;

  static const _autoLockSeconds = 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initial = _tabs.indexWhere((t) => t.label == 'Tagebuch');
    _controller = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: initial < 0 ? 0 : initial,
    );
    _controller.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onTabChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _lastActiveTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      if (_lastActiveTime != null) {
        final elapsed = DateTime.now().difference(_lastActiveTime!).inSeconds;
        if (elapsed > _autoLockSeconds) {
          setState(() => _photosUnlocked = false);
        }
      }
    }
  }

  void _onTabChanged() {
    if (_controller.indexIsChanging) return;
    final tab = _tabs[_controller.index];
    if (tab.label == 'Fotos' && !_photosUnlocked) {
      _requestPhotoAccess();
    }
  }

  Future<void> _requestPhotoAccess() async {
    final available = await AppLockService.isAvailable();
    if (!available) {
      // No biometrics on this device — allow access
      if (mounted) setState(() => _photosUnlocked = true);
      return;
    }
    final ok = await AppLockService.authenticate();
    if (mounted) setState(() => _photosUnlocked = ok);
    if (!ok && mounted) {
      // Bounce back to Tagebuch
      _controller.animateTo(0);
    }
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
          if (t.label == 'Fotos') {
            return _photosUnlocked
                ? const PhotosTab()
                : _LockedTab(onUnlock: _requestPhotoAccess);
          }
          return switch (t.label) {
            'Tagebuch' => const DiaryTab(),
            'Gewicht' => const WeightTab(),
            'Maße' => const MeasurementsTab(),
            'Workouts' => const WorkoutsTab(),
            'Ziele' => const GoalsTab(),
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

class _LockedTab extends StatelessWidget {
  final VoidCallback onUnlock;
  const _LockedTab({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outlined, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('Privater Bereich',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Dieser Bereich ist durch Biometrie\noder Geräte-PIN geschützt.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onUnlock,
              icon: const Icon(Icons.fingerprint),
              label: const Text('Entsperren'),
            ),
          ],
        ),
      ),
    );
  }
}
