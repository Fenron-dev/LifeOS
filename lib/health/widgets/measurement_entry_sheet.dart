import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../providers/measurements_provider.dart';

/// Bottom-sheet form for a single body-measurement session. All six metrics
/// (chest / waist / hip / thigh / arm / neck) are optional cm fields — the
/// user can capture any subset they have available.
///
/// Pass [editLog] to open in edit mode — all fields pre-fill and save calls
/// [MeasurementsOpsNotifier.updateLog] instead of [logMeasurement].
class MeasurementEntrySheet extends ConsumerStatefulWidget {
  final BodyMeasurement? editLog;

  const MeasurementEntrySheet({super.key, this.editLog});

  @override
  ConsumerState<MeasurementEntrySheet> createState() =>
      _MeasurementEntrySheetState();
}

class _MeasurementEntrySheetState
    extends ConsumerState<MeasurementEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _chest = TextEditingController();
  final _waist = TextEditingController();
  final _hip = TextEditingController();
  final _thigh = TextEditingController();
  final _arm = TextEditingController();
  final _neck = TextEditingController();
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
      _chest.text = _fmt(log.chestCm);
      _waist.text = _fmt(log.waistCm);
      _hip.text = _fmt(log.hipCm);
      _thigh.text = _fmt(log.thighCm);
      _arm.text = _fmt(log.armCm);
      _neck.text = _fmt(log.neckCm);
      _notes.text = log.notes ?? '';
    }
  }

  String _fmt(double? v) =>
      v == null ? '' : v.toStringAsFixed(1).replaceAll('.0', '');

  @override
  void dispose() {
    _chest.dispose();
    _waist.dispose();
    _hip.dispose();
    _thigh.dispose();
    _arm.dispose();
    _neck.dispose();
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

  bool get _hasAnyValue =>
      [_chest, _waist, _hip, _thigh, _arm, _neck]
          .any((c) => c.text.trim().isNotEmpty);

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_hasAnyValue) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mindestens einen Messwert eingeben.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isEditMode) {
        await ref.read(measurementsOpsProvider.notifier).updateLog(
              BodyMeasurementsCompanion(
                id: Value(widget.editLog!.id),
                loggedAt: Value(_loggedAt),
                chestCm: Value(_parse(_chest)),
                waistCm: Value(_parse(_waist)),
                hipCm: Value(_parse(_hip)),
                thighCm: Value(_parse(_thigh)),
                armCm: Value(_parse(_arm)),
                neckCm: Value(_parse(_neck)),
                notes: Value(
                    _notes.text.trim().isEmpty ? null : _notes.text.trim()),
              ),
            );
      } else {
        await ref.read(measurementsOpsProvider.notifier).logMeasurement(
              loggedAt: _loggedAt,
              chestCm: _parse(_chest),
              waistCm: _parse(_waist),
              hipCm: _parse(_hip),
              thighCm: _parse(_thigh),
              armCm: _parse(_arm),
              neckCm: _parse(_neck),
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
                _isEditMode ? 'Maße bearbeiten' : 'Maße erfassen',
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
              const SizedBox(height: 16),
              Text('Körpermaße in cm (optional)',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              _CmRow(
                left: _CmField(controller: _chest, label: 'Brust'),
                right: _CmField(controller: _waist, label: 'Taille'),
              ),
              const SizedBox(height: 12),
              _CmRow(
                left: _CmField(controller: _hip, label: 'Hüfte'),
                right:
                    _CmField(controller: _thigh, label: 'Oberschenkel'),
              ),
              const SizedBox(height: 12),
              _CmRow(
                left: _CmField(controller: _arm, label: 'Arm / Bizeps'),
                right: _CmField(controller: _neck, label: 'Nacken'),
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
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
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

class _CmRow extends StatelessWidget {
  final Widget left;
  final Widget right;
  const _CmRow({required this.left, required this.right});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      );
}

class _CmField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const _CmField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixText: 'cm',
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
          if (d <= 0 || d > 300) return '1–300 cm';
          return null;
        },
      );
}
