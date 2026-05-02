import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../providers/weight_provider.dart';

/// Bottom-sheet form for a single weigh-in. Covers the full smart-scale
/// payload (weight + body-fat / muscle / visceral / water / bone). Only the
/// weight field is required — every extra metric is optional.
///
/// Pass [editLog] to open in edit mode — all fields pre-fill and save calls
/// [WeightOpsNotifier.updateLog] instead of [logWeight].
class WeightEntrySheet extends ConsumerStatefulWidget {
  final BodyWeightLog? editLog;

  const WeightEntrySheet({super.key, this.editLog});

  @override
  ConsumerState<WeightEntrySheet> createState() => _WeightEntrySheetState();
}

class _WeightEntrySheetState extends ConsumerState<WeightEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _weight = TextEditingController();
  final _bodyFat = TextEditingController();
  final _muscle = TextEditingController();
  final _visceral = TextEditingController();
  final _water = TextEditingController();
  final _bone = TextEditingController();
  final _notes = TextEditingController();

  DateTime _loggedAt = DateTime.now();
  bool _saving = false;

  bool get _isEditMode => widget.editLog != null;

  @override
  void initState() {
    super.initState();
    final log = widget.editLog;
    if (log != null) {
      _loggedAt = log.loggedAt;
      _weight.text = log.weightKg.toStringAsFixed(1).replaceAll('.0', '');
      _bodyFat.text = _fmt(log.bodyFatPct);
      _muscle.text = _fmt(log.muscleMassPct);
      _visceral.text = _fmt(log.visceralFat);
      _water.text = _fmt(log.waterPct);
      _bone.text = _fmt(log.boneMassKg);
      _notes.text = log.notes ?? '';
    }
  }

  String _fmt(double? v) =>
      v == null ? '' : v.toStringAsFixed(1).replaceAll('.0', '');

  @override
  void dispose() {
    _weight.dispose();
    _bodyFat.dispose();
    _muscle.dispose();
    _visceral.dispose();
    _water.dispose();
    _bone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _loggedAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now(),
      locale: const Locale('de'),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_loggedAt),
    );
    if (time == null) return;
    setState(() {
      _loggedAt =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  double? _parse(TextEditingController c) {
    final raw = c.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      if (_isEditMode) {
        await ref.read(weightOpsProvider.notifier).updateLog(
              BodyWeightLogsCompanion(
                id: Value(widget.editLog!.id),
                loggedAt: Value(_loggedAt),
                weightKg: Value(_parse(_weight)!),
                bodyFatPct: Value(_parse(_bodyFat)),
                muscleMassPct: Value(_parse(_muscle)),
                visceralFat: Value(_parse(_visceral)),
                waterPct: Value(_parse(_water)),
                boneMassKg: Value(_parse(_bone)),
                notes: Value(
                    _notes.text.trim().isEmpty ? null : _notes.text.trim()),
              ),
            );
      } else {
        await ref.read(weightOpsProvider.notifier).logWeight(
              loggedAt: _loggedAt,
              weightKg: _parse(_weight)!,
              bodyFatPct: _parse(_bodyFat),
              muscleMassPct: _parse(_muscle),
              visceralFat: _parse(_visceral),
              waterPct: _parse(_water),
              boneMassKg: _parse(_bone),
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            );
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 16 + inset,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _isEditMode ? 'Wiegung bearbeiten' : 'Wiegen erfassen',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _pickDateTime,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Zeitpunkt',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.schedule),
                  ),
                  child: Text(
                    DateFormat.yMMMMd('de_DE').add_Hm().format(_loggedAt),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _weight,
                autofocus: !_isEditMode,
                decoration: const InputDecoration(
                  labelText: 'Gewicht *',
                  suffixText: 'kg',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.monitor_weight_outlined),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                validator: (v) {
                  final d = double.tryParse(
                      (v ?? '').trim().replaceAll(',', '.'));
                  if (d == null || d <= 0) return 'Pflichtfeld';
                  if (d < 20 || d > 400) return 'Plausibler Wert eingeben';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text('Körperzusammensetzung (optional)',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _SmartRow(
                left: _PctField(
                    controller: _bodyFat,
                    label: 'Körperfett',
                    hint: 'KFA'),
                right: _PctField(
                    controller: _muscle,
                    label: 'Muskelmasse',
                    hint: 'Muskel'),
              ),
              const SizedBox(height: 12),
              _SmartRow(
                left: _NumberField(
                    controller: _visceral,
                    label: 'Viszeralfett',
                    hint: 'Index'),
                right: _PctField(
                    controller: _water,
                    label: 'Wasseranteil',
                    hint: 'Wasser'),
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: _bone,
                label: 'Knochenmasse',
                hint: 'kg',
                suffix: 'kg',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Notiz (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note_outlined),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Abbrechen'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Speichern'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmartRow extends StatelessWidget {
  final Widget left;
  final Widget right;
  const _SmartRow({required this.left, required this.right});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      );
}

class _PctField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  const _PctField(
      {required this.controller, required this.label, required this.hint});

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          suffixText: '%',
        ),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        validator: (v) {
          if ((v ?? '').trim().isEmpty) return null;
          final d = double.tryParse(v!.trim().replaceAll(',', '.'));
          if (d == null) return 'Ungültig';
          if (d < 0 || d > 100) return '0–100 %';
          return null;
        },
      );
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final String? suffix;
  const _NumberField({
    required this.controller,
    required this.label,
    required this.hint,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          suffixText: suffix,
        ),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        validator: (v) {
          if ((v ?? '').trim().isEmpty) return null;
          final d = double.tryParse(v!.trim().replaceAll(',', '.'));
          if (d == null) return 'Ungültig';
          return null;
        },
      );
}
