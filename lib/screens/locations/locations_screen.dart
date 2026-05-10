import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../../providers/locations_provider.dart';
import '../../widgets/entity_photo_section.dart';

class LocationsScreen extends ConsumerWidget {
  const LocationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsAsync = ref.watch(allLocationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Lagerorte')),
      body: locationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (locations) {
          if (locations.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.place_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  const Text('Noch keine Lagerorte'),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => _showAddDialog(context, ref),
                    icon: const Icon(Icons.add),
                    label: const Text('Lagerort anlegen'),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: locations.length,
            itemBuilder: (context, i) =>
                _LocationTile(location: locations[i], allLocations: locations),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddDialog(context, ref),
        tooltip: 'Lagerort hinzufügen',
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => const _LocationDialog(),
    );
  }
}

class _LocationTile extends ConsumerWidget {
  final Location location;
  final List<Location> allLocations;
  const _LocationTile({required this.location, required this.allLocations});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parent = location.parentId != null
        ? allLocations.where((l) => l.id == location.parentId).firstOrNull
        : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(child: Icon(_locationIcon(location))),
        title: Text(location.name),
        subtitle: parent != null ? Text('in: ${parent.name}') : null,
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'photos') {
              _showPhotos(context, location);
            } else if (v == 'edit') {
              _showEditDialog(context, ref, location);
            } else if (v == 'delete') {
              await _confirmDelete(context, ref, location);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'photos',
              child: Row(children: [
                Icon(Icons.photo_library_outlined),
                SizedBox(width: 8),
                Text('Fotos'),
              ]),
            ),
            const PopupMenuItem(
              value: 'edit',
              child: Row(children: [
                Icon(Icons.edit_outlined),
                SizedBox(width: 8),
                Text('Bearbeiten'),
              ]),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete_outline, color: Colors.red),
                SizedBox(width: 8),
                Text('Löschen', style: TextStyle(color: Colors.red)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  IconData _locationIcon(Location loc) => switch (loc.locationType) {
        'fridge' => Icons.kitchen,
        'freezer' => Icons.ac_unit,
        _ => Icons.inventory_2_outlined,
      };

  void _showPhotos(BuildContext context, Location loc) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 20, 16, MediaQuery.viewInsetsOf(ctx).bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.name,
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            EntityPhotoSection(entityId: loc.id, entityType: 'location'),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, Location loc) {
    showDialog(
      context: context,
      builder: (_) => _LocationDialog(location: loc),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Location loc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Lagerort löschen?'),
        content: Text('„${loc.name}" wird gelöscht.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Löschen', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(locationsNotifierProvider.notifier).deleteLocation(loc.id);
    }
  }
}

class _LocationDialog extends ConsumerStatefulWidget {
  final Location? location;
  const _LocationDialog({this.location});

  @override
  ConsumerState<_LocationDialog> createState() => _LocationDialogState();
}

class _LocationDialogState extends ConsumerState<_LocationDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _notesCtrl;
  String? _parentId;
  String _locationType = 'normal';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.location?.name ?? '');
    _notesCtrl = TextEditingController(text: widget.location?.notes ?? '');
    _parentId = widget.location?.parentId;
    _locationType = widget.location?.locationType ?? 'normal';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final notifier = ref.read(locationsNotifierProvider.notifier);
      if (widget.location == null) {
        await notifier.createLocation(
          name: _nameCtrl.text.trim(),
          parentId: _parentId,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          locationType: _locationType,
        );
      } else {
        await notifier.updateLocation(
          id: widget.location!.id,
          name: _nameCtrl.text.trim(),
          parentId: _parentId,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          locationType: _locationType,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationsAsync = ref.watch(allLocationsProvider);
    final locations = locationsAsync.valueOrNull ?? [];
    // Exclude self from parent options
    final parentOptions =
        locations.where((l) => l.id != widget.location?.id).toList();
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return AlertDialog(
      title: Text(
          widget.location == null ? 'Lagerort anlegen' : 'Lagerort bearbeiten'),
      content: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'Name *'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(labelText: 'Übergeordneter Ort'),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _parentId,
                isDense: true,
                items: [
                  const DropdownMenuItem(value: null, child: Text('— keiner —')),
                  ...parentOptions.map((l) =>
                      DropdownMenuItem(value: l.id, child: Text(l.name))),
                ],
                onChanged: (v) => setState(() => _parentId = v),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'normal',
                icon: Icon(Icons.inventory_2_outlined),
                label: Text('Normal'),
              ),
              ButtonSegment(
                value: 'fridge',
                icon: Icon(Icons.kitchen),
                label: Text('Kühlschrank'),
              ),
              ButtonSegment(
                value: 'freezer',
                icon: Icon(Icons.ac_unit),
                label: Text('Gefrierer'),
              ),
            ],
            selected: {_locationType},
            onSelectionChanged: (s) =>
                setState(() => _locationType = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(labelText: 'Notiz'),
          ),
        ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Speichern'),
        ),
      ],
    );
  }
}
