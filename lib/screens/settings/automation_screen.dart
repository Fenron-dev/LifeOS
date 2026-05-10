import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../../providers/automation_provider.dart';

// ── Trigger / action labels ───────────────────────────────────────────────────

String _triggerLabel(String type) => switch (type) {
      'manual' => 'Manuell',
      'scheduled' => 'Geplant',
      'event' => 'Bei Ereignis',
      'threshold' => 'Bei Schwellenwert',
      _ => type,
    };

IconData _triggerIcon(String type) => switch (type) {
      'manual' => Icons.play_circle_outline,
      'scheduled' => Icons.schedule,
      'event' => Icons.bolt_outlined,
      'threshold' => Icons.trending_down,
      _ => Icons.settings,
    };

String _triggerDescription(AutomationRule r) {
  final cfg = Map<String, dynamic>.from(
      jsonDecode(r.triggerConfig) as Map? ?? {});
  return switch (r.triggerType) {
    'scheduled' => () {
        final time = cfg['time'] as String? ?? '08:00';
        final repeat = cfg['repeat'] as String? ?? 'daily';
        final repeatLabel =
            repeat == 'daily' ? 'täglich' : 'wöchentlich';
        return '$repeatLabel um $time Uhr';
      }(),
    'event' => cfg['eventType'] as String? ?? '–',
    'threshold' => () {
        final category = cfg['category'] as String? ?? '';
        return category.isEmpty ? 'Wenn Bestand unter Minimum' : 'Kategorie: $category';
      }(),
    _ => '–',
  };
}

String _actionsDescription(AutomationRule r) {
  final actions = List<Map<String, dynamic>>.from(
      jsonDecode(r.actions) as List? ?? []);
  if (actions.isEmpty) return 'Keine Aktionen';
  return actions.map((a) => switch (a['type']) {
        'create_task' => 'Aufgabe: ${a['title'] ?? '–'}',
        'notify' => 'Benachrichtigung',
        _ => a['type'] as String? ?? '?',
      }).join(' • ');
}

// ── Screen ────────────────────────────────────────────────────────────────────

class AutomationScreen extends ConsumerWidget {
  const AutomationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(automationRulesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Automation'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Neue Regel',
            onPressed: () => _showDialog(context, ref, null),
          ),
        ],
      ),
      body: rulesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (rules) {
          if (rules.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  const Text('Keine Automations'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _showDialog(context, ref, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Regel erstellen'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: rules.length,
            itemBuilder: (context, i) => _RuleTile(rule: rules[i]),
          );
        },
      ),
    );
  }

  void _showDialog(
      BuildContext context, WidgetRef ref, AutomationRule? rule) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RuleDialog(rule: rule),
    );
  }
}

// ── Rule tile ─────────────────────────────────────────────────────────────────

class _RuleTile extends ConsumerWidget {
  final AutomationRule rule;
  const _RuleTile({required this.rule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(automationNotifierProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              _triggerIcon(rule.triggerType),
              color: rule.enabled ? cs.primary : cs.outline,
            ),
            title: Text(
              rule.name,
              style: rule.enabled
                  ? null
                  : TextStyle(color: cs.outline),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_triggerLabel(rule.triggerType)}'
                  '${rule.triggerType != 'manual' ? ' • ${_triggerDescription(rule)}' : ''}',
                  style:
                      Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  _actionsDescription(rule),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.outline),
                ),
              ],
            ),
            trailing: Switch(
              value: rule.enabled,
              onChanged: (_) => notifier.toggleEnabled(rule),
            ),
          ),
          const Divider(height: 1),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Ausführen'),
                onPressed: () => _runNow(context, ref),
              ),
              TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Bearbeiten'),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => _RuleDialog(rule: rule),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    size: 18, color: Colors.red),
                onPressed: () => _confirmDelete(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _runNow(BuildContext context, WidgetRef ref) async {
    final results = await ref
        .read(automationNotifierProvider.notifier)
        .runNow(rule);
    if (!context.mounted) return;
    final msg = results.isEmpty ? 'Keine Aktionen ausgeführt.' : results.join('\n');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Regel löschen?'),
        content: Text('„${rule.name}" wird dauerhaft gelöscht.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Abbrechen')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Löschen',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await ref
          .read(automationNotifierProvider.notifier)
          .delete(rule.id);
    }
  }
}

// ── Rule dialog ───────────────────────────────────────────────────────────────

class _RuleDialog extends ConsumerStatefulWidget {
  final AutomationRule? rule;
  const _RuleDialog({this.rule});

  @override
  ConsumerState<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends ConsumerState<_RuleDialog> {
  late final TextEditingController _nameCtrl;
  String _triggerType = 'manual';
  bool _enabled = true;
  bool _saving = false;

  // Trigger config fields
  String _scheduledTime = '08:00';
  String _scheduledRepeat = 'daily';
  String _eventType = 'item_expiring';

  // Actions list
  final List<Map<String, dynamic>> _actions = [];

  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    _nameCtrl = TextEditingController(text: r?.name ?? '');
    _triggerType = r?.triggerType ?? 'manual';
    _enabled = r?.enabled ?? true;

    if (r != null) {
      final cfg = Map<String, dynamic>.from(
          jsonDecode(r.triggerConfig) as Map? ?? {});
      _scheduledTime = cfg['time'] as String? ?? '08:00';
      _scheduledRepeat = cfg['repeat'] as String? ?? 'daily';
      _eventType = cfg['eventType'] as String? ?? 'item_expiring';
      _actions.addAll(List<Map<String, dynamic>>.from(
          jsonDecode(r.actions) as List? ?? []));
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildTriggerConfig() => switch (_triggerType) {
        'scheduled' => {'time': _scheduledTime, 'repeat': _scheduledRepeat},
        'event' => {'eventType': _eventType},
        _ => {},
      };

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final notifier = ref.read(automationNotifierProvider.notifier);
      final cfg = _buildTriggerConfig();
      if (widget.rule == null) {
        await notifier.create(
          name: _nameCtrl.text.trim(),
          triggerType: _triggerType,
          triggerConfig: cfg,
          actions: _actions,
          enabled: _enabled,
        );
      } else {
        await notifier.save(widget.rule!.copyWith(
          name: _nameCtrl.text.trim(),
          triggerType: _triggerType,
          triggerConfig: jsonEncode(cfg),
          actions: jsonEncode(_actions),
          enabled: _enabled,
        ));
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.rule == null ? 'Neue Regel' : 'Regel bearbeiten',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Switch(
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                const Text('Aktiv'),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name *'),
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),

            // Trigger type
            Text('Auslöser',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['manual', 'scheduled', 'event'].map((t) {
                final sel = _triggerType == t;
                return ChoiceChip(
                  avatar: Icon(_triggerIcon(t), size: 16),
                  label: Text(_triggerLabel(t)),
                  selected: sel,
                  onSelected: (_) =>
                      setState(() => _triggerType = t),
                );
              }).toList(),
            ),

            // Trigger config
            if (_triggerType == 'scheduled') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Wiederholen', isDense: true),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _scheduledRepeat,
                          isDense: true,
                          items: const [
                            DropdownMenuItem(
                                value: 'daily',
                                child: Text('Täglich')),
                            DropdownMenuItem(
                                value: 'weekly',
                                child: Text('Wöchentlich')),
                          ],
                          onChanged: (v) =>
                              setState(() => _scheduledRepeat = v!),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Uhrzeit'),
                      subtitle: Text(_scheduledTime),
                      onTap: () async {
                        final parts = _scheduledTime.split(':');
                        final t = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(
                            hour: int.tryParse(parts[0]) ?? 8,
                            minute: int.tryParse(parts[1]) ?? 0,
                          ),
                        );
                        if (t != null && mounted) {
                          setState(() => _scheduledTime =
                              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],

            if (_triggerType == 'event') ...[
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Ereignis', isDense: true),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _eventType,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(
                          value: 'item_expiring',
                          child: Text('Artikel läuft ab')),
                      DropdownMenuItem(
                          value: 'item_low_stock',
                          child: Text('Artikel unter Mindestbestand')),
                    ],
                    onChanged: (v) =>
                        setState(() => _eventType = v!),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Actions
            Row(
              children: [
                Text('Aktionen',
                    style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Hinzufügen'),
                  onPressed: () => _addAction(context),
                ),
              ],
            ),

            if (_actions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Noch keine Aktionen.',
                    style: TextStyle(color: cs.outline)),
              ),

            ..._actions.asMap().entries.map((entry) {
              final i = entry.key;
              final a = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    a['type'] == 'create_task'
                        ? Icons.task_outlined
                        : Icons.notifications_outlined,
                    size: 18,
                  ),
                  title: Text(_actionLabel(a),
                      style: Theme.of(context).textTheme.bodySmall),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () =>
                        setState(() => _actions.removeAt(i)),
                  ),
                ),
              );
            }),

            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  String _actionLabel(Map<String, dynamic> a) => switch (a['type']) {
        'create_task' =>
          'Aufgabe: ${a['title'] ?? '–'} (${a['priority'] ?? 'medium'})',
        'notify' => 'Benachrichtigung: ${a['message'] ?? '–'}',
        _ => a['type'] as String? ?? '?',
      };

  Future<void> _addAction(BuildContext context) async {
    final action = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _AddActionDialog(),
    );
    if (action != null) setState(() => _actions.add(action));
  }
}

// ── Add action dialog ─────────────────────────────────────────────────────────

class _AddActionDialog extends StatefulWidget {
  const _AddActionDialog();

  @override
  State<_AddActionDialog> createState() => _AddActionDialogState();
}

class _AddActionDialogState extends State<_AddActionDialog> {
  String _type = 'create_task';
  final _titleCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();
  String _priority = 'medium';
  int _daysOffset = 0;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Aktion hinzufügen'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InputDecorator(
              decoration:
                  const InputDecoration(labelText: 'Typ', isDense: true),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _type,
                  isDense: true,
                  items: const [
                    DropdownMenuItem(
                        value: 'create_task',
                        child: Text('Aufgabe erstellen')),
                    DropdownMenuItem(
                        value: 'notify',
                        child: Text('Benachrichtigung')),
                  ],
                  onChanged: (v) => setState(() => _type = v!),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_type == 'create_task') ...[
              TextField(
                controller: _titleCtrl,
                decoration:
                    const InputDecoration(labelText: 'Aufgaben-Titel *'),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Priorität', isDense: true),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _priority,
                    isDense: true,
                    items: const [
                      DropdownMenuItem(value: 'high', child: Text('Hoch')),
                      DropdownMenuItem(
                          value: 'medium', child: Text('Mittel')),
                      DropdownMenuItem(
                          value: 'low', child: Text('Niedrig')),
                    ],
                    onChanged: (v) => setState(() => _priority = v!),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fälligkeit'),
                subtitle: Text(
                  _daysOffset == 0
                      ? 'Heute'
                      : 'In $_daysOffset Tag${_daysOffset == 1 ? '' : 'en'}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove),
                      onPressed: _daysOffset > 0
                          ? () =>
                              setState(() => _daysOffset--)
                          : null,
                    ),
                    Text('$_daysOffset'),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () =>
                          setState(() => _daysOffset++),
                    ),
                  ],
                ),
              ),
            ],
            if (_type == 'notify')
              TextField(
                controller: _msgCtrl,
                decoration: const InputDecoration(
                    labelText: 'Nachricht *'),
                autofocus: true,
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Abbrechen')),
        FilledButton(
          onPressed: () {
            Map<String, dynamic>? result;
            if (_type == 'create_task' &&
                _titleCtrl.text.trim().isNotEmpty) {
              result = {
                'type': 'create_task',
                'title': _titleCtrl.text.trim(),
                'priority': _priority,
                'daysOffset': _daysOffset,
              };
            } else if (_type == 'notify' &&
                _msgCtrl.text.trim().isNotEmpty) {
              result = {
                'type': 'notify',
                'message': _msgCtrl.text.trim(),
              };
            }
            Navigator.of(context).pop(result);
          },
          child: const Text('Hinzufügen'),
        ),
      ],
    );
  }
}
