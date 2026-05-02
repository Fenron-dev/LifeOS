import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../providers/profile_provider.dart';

/// Phase 6.1 — profile tab. Holds the static personal data the BMR/TDEE
/// calculation depends on: birth date, sex, height, activity level, plus
/// the weight goals (start / target). Calorie / water / macro targets get
/// their own UI in Phase 6.6 (Ziele-Tab).
class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  final _displayName = TextEditingController();
  final _height = TextEditingController();
  final _startWeight = TextEditingController();
  final _targetWeight = TextEditingController();
  final _calorieGoal = TextEditingController();
  final _proteinTarget = TextEditingController();
  final _carbsTarget = TextEditingController();
  final _fatTarget = TextEditingController();

  DateTime? _birthDate;
  String? _sex;
  double _activity = 1.4;

  bool _hydrated = false;
  bool _saving = false;

  void _hydrate(UserProfileData? p) {
    if (_hydrated || p == null) return;
    _hydrated = true;
    _displayName.text = p.displayName ?? '';
    _height.text =
        p.heightCm == null ? '' : p.heightCm!.toStringAsFixed(1).replaceAll('.0', '');
    _startWeight.text = p.startWeightKg == null
        ? ''
        : p.startWeightKg!.toStringAsFixed(1).replaceAll('.0', '');
    _targetWeight.text = p.targetWeightKg == null
        ? ''
        : p.targetWeightKg!.toStringAsFixed(1).replaceAll('.0', '');
    _birthDate = p.birthDate;
    _sex = p.sex;
    _activity = p.activityLevel;
    if (p.dailyCalorieGoal != null) {
      _calorieGoal.text = p.dailyCalorieGoal!.toString();
    }
    if (p.proteinTargetG != null) {
      _proteinTarget.text =
          p.proteinTargetG!.toStringAsFixed(0);
    }
    if (p.carbsTargetG != null) {
      _carbsTarget.text = p.carbsTargetG!.toStringAsFixed(0);
    }
    if (p.fatTargetG != null) {
      _fatTarget.text = p.fatTargetG!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _displayName.dispose();
    _height.dispose();
    _startWeight.dispose();
    _targetWeight.dispose();
    _calorieGoal.dispose();
    _proteinTarget.dispose();
    _carbsTarget.dispose();
    _fatTarget.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController c) {
    final raw = c.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  Future<void> _pickBirthDate() async {
    final initial = _birthDate ?? DateTime(1990, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('de'),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final kcalGoalRaw = int.tryParse(_calorieGoal.text.trim());
      await ref.read(profileOpsProvider.notifier).save(
            displayName: Value(_displayName.text.trim().isEmpty
                ? null
                : _displayName.text.trim()),
            birthDate: Value(_birthDate),
            sex: Value(_sex),
            heightCm: Value(_parse(_height)),
            activityLevel: Value(_activity),
            startWeightKg: Value(_parse(_startWeight)),
            targetWeightKg: Value(_parse(_targetWeight)),
            dailyCalorieGoal: Value(kcalGoalRaw),
            proteinTargetG: Value(_parse(_proteinTarget)),
            carbsTargetG: Value(_parse(_carbsTarget)),
            fatTargetG: Value(_parse(_fatTarget)),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil gespeichert')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);
    final derived = ref.watch(healthDerivedTargetsProvider);
    return profileAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Fehler: $e')),
      data: (p) {
        _hydrate(p);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _DerivedCard(d: derived),
            const SizedBox(height: 16),
            Text('Persönliche Angaben',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _displayName,
              decoration: const InputDecoration(
                labelText: 'Anzeigename (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickBirthDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Geburtsdatum',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.cake_outlined),
                ),
                child: Text(
                  _birthDate == null
                      ? 'Tippen, um auszuwählen'
                      : DateFormat.yMMMMd('de_DE').format(_birthDate!),
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _sex,
              decoration: const InputDecoration(
                labelText: 'Geschlecht',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wc),
              ),
              items: const [
                DropdownMenuItem(value: 'male', child: Text('Männlich')),
                DropdownMenuItem(value: 'female', child: Text('Weiblich')),
                DropdownMenuItem(value: 'diverse', child: Text('Divers')),
                DropdownMenuItem(
                    value: null, child: Text('Keine Angabe')),
              ],
              onChanged: (v) => setState(() => _sex = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _height,
              decoration: const InputDecoration(
                labelText: 'Körpergröße',
                suffixText: 'cm',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.height),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
            ),
            const SizedBox(height: 16),
            Text('Aktivitätslevel',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              _activityLabel(_activity),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            Slider(
              value: _activity,
              min: 1.2,
              max: 1.9,
              divisions: 7,
              label: _activity.toStringAsFixed(2),
              onChanged: (v) => setState(() => _activity = v),
            ),
            const SizedBox(height: 16),
            Text('Gewichtsziel',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _startWeight,
                    decoration: const InputDecoration(
                      labelText: 'Startgewicht',
                      suffixText: 'kg',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _targetWeight,
                    decoration: const InputDecoration(
                      labelText: 'Zielgewicht',
                      suffixText: 'kg',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Tagesziele',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _calorieGoal,
              decoration: const InputDecoration(
                labelText: 'Kalorienziel',
                suffixText: 'kcal',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_fire_department_outlined),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _proteinTarget,
                    decoration: const InputDecoration(
                      labelText: 'Protein',
                      suffixText: 'g',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _carbsTarget,
                    decoration: const InputDecoration(
                      labelText: 'Kohlenhydrate',
                      suffixText: 'g',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _fatTarget,
                    decoration: const InputDecoration(
                      labelText: 'Fett',
                      suffixText: 'g',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: const Text('Profil speichern'),
            ),
          ],
        );
      },
    );
  }

  static String _activityLabel(double v) {
    if (v < 1.3) return 'Sitzend (1.2) – kaum Bewegung';
    if (v < 1.45) return 'Leicht aktiv (1.4) – Bürojob, Spaziergänge';
    if (v < 1.65) return 'Moderat aktiv (1.55) – Sport 3–5×/Woche';
    if (v < 1.8) return 'Stark aktiv (1.75) – tägliches Training';
    return 'Extrem aktiv (1.9) – Leistungssport / körperliche Arbeit';
  }
}

class _DerivedCard extends StatelessWidget {
  final HealthDerivedTargets d;
  const _DerivedCard({required this.d});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt0 = NumberFormat.decimalPattern('de_DE')
      ..maximumFractionDigits = 0;
    final fmt1 = NumberFormat.decimalPattern('de_DE')
      ..maximumFractionDigits = 1;

    return Card(
      color: cs.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calculate_outlined,
                    color: cs.onSecondaryContainer),
                const SizedBox(width: 8),
                Text('Berechnete Werte',
                    style: TextStyle(
                        color: cs.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            _row('Alter',
                d.ageYears == null ? '—' : '${d.ageYears} Jahre', cs),
            _row('BMI', d.bmi == null ? '—' : fmt1.format(d.bmi!), cs),
            _row('BMR (Grundumsatz)',
                d.bmr == null ? '—' : '${fmt0.format(d.bmr!)} kcal', cs),
            _row('TDEE (Tagesumsatz)',
                d.tdee == null ? '—' : '${fmt0.format(d.tdee!)} kcal', cs),
            _row(
              'Empf. Tageskalorien',
              d.suggestedDailyKcal == null
                  ? '—'
                  : '${fmt0.format(d.suggestedDailyKcal)} kcal',
              cs,
              emphasize: true,
            ),
            if (d.suggestedDailyKcal == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Trage Geburtsdatum, Größe, Gewicht und Geschlecht ein, um Berechnung zu aktivieren.',
                  style: TextStyle(
                      color: cs.onSecondaryContainer.withValues(alpha: 0.8),
                      fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v, ColorScheme cs, {bool emphasize = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
              child: Text(k,
                  style: TextStyle(
                      color: cs.onSecondaryContainer.withValues(alpha: 0.9)))),
          Text(v,
              style: TextStyle(
                  color: cs.onSecondaryContainer,
                  fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
                  fontSize: emphasize ? 18 : 14)),
        ],
      ),
    );
  }
}
