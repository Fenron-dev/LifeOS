import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../db/database.dart';
import '../providers/photos_provider.dart';

/// Phase 6.7 – Private encrypted body photo gallery.
class PhotosTab extends ConsumerWidget {
  const PhotosTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photosAsync = ref.watch(bodyPhotosProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Fotos'),
        actions: [
          if (photosAsync.valueOrNull != null &&
              photosAsync.value!.length >= 2)
            IconButton(
              icon: const Icon(Icons.compare),
              tooltip: 'Vorher / Nachher',
              onPressed: () => _openBeforeAfter(context, ref,
                  photosAsync.value!),
            ),
        ],
      ),
      body: photosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Fehler: $e')),
        data: (photos) => photos.isEmpty
            ? _EmptyState(onAdd: () => _addPhoto(context, ref))
            : _PhotoGrid(photos: photos),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addPhoto(context, ref),
        tooltip: 'Foto hinzufügen',
        child: const Icon(Icons.add_a_photo_outlined),
      ),
    );
  }

  Future<void> _addPhoto(BuildContext context, WidgetRef ref) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Kamera'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Galerie'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    final type = await _pickPhotoType(context);
    if (type == null || !context.mounted) return;

    await ref.read(photoOpsProvider.notifier).addPhoto(
          source: source,
          photoType: type,
        );
  }

  Future<String?> _pickPhotoType(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Fotowinkel'),
        children: _photoTypes.map((t) {
          return SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(t.$1),
            child: Row(
              children: [
                Text(t.$2, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 12),
                Text(t.$3),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  void _openBeforeAfter(
      BuildContext context, WidgetRef ref, List<BodyPhoto> photos) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _BeforeAfterScreen(photos: photos),
      ),
    );
  }
}

const _photoTypes = <(String, String, String)>[
  ('front', '⬛', 'Vorderseite'),
  ('side', '↔', 'Seite'),
  ('back', '🔲', 'Rückseite'),
  ('face', '😊', 'Gesicht'),
  ('other', '📷', 'Sonstiges'),
];

String _typeLabel(String type) => switch (type) {
      'front' => 'Vorne',
      'side' => 'Seite',
      'back' => 'Hinten',
      'face' => 'Gesicht',
      _ => 'Sonstiges',
    };

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outlined,
                size: 64, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('Noch keine Fotos',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Fotos sind AES-256 verschlüsselt und\nwerden nur lokal gespeichert.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('Erstes Foto hinzufügen'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Gallery grid ──────────────────────────────────────────────────────────────

class _PhotoGrid extends ConsumerWidget {
  final List<BodyPhoto> photos;
  const _PhotoGrid({required this.photos});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: photos.length,
      itemBuilder: (context, i) => _PhotoTile(photo: photos[i]),
    );
  }
}

// ── Single photo tile ─────────────────────────────────────────────────────────

class _PhotoTile extends ConsumerStatefulWidget {
  final BodyPhoto photo;
  const _PhotoTile({required this.photo});

  @override
  ConsumerState<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends ConsumerState<_PhotoTile> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes =
        await ref.read(photoOpsProvider.notifier).loadPhotoBytes(widget.photo);
    if (mounted) setState(() { _bytes = bytes; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _openDetail(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_loading)
              Container(
                color: cs.surfaceContainerHighest,
                child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_bytes == null)
              Container(
                color: cs.errorContainer,
                child: Icon(Icons.broken_image_outlined,
                    color: cs.onErrorContainer),
              )
            else
              Image.memory(_bytes!, fit: BoxFit.cover),
            Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _typeLabel(widget.photo.photoType),
                  style:
                      const TextStyle(color: Colors.white, fontSize: 9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    if (_bytes == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _PhotoDetailScreen(
          photo: widget.photo, bytes: _bytes!),
    ));
  }
}

// ── Photo detail screen ───────────────────────────────────────────────────────

class _PhotoDetailScreen extends ConsumerWidget {
  final BodyPhoto photo;
  final Uint8List bytes;
  const _PhotoDetailScreen({required this.photo, required this.bytes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat.yMMMd('de_DE').add_Hm();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_typeLabel(photo.photoType)} · ${fmt.format(photo.takenAt)}',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Löschen',
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              child: Center(
                child: Image.memory(bytes),
              ),
            ),
          ),
          if (photo.weightAtPhotoKg != null || photo.notes != null)
            Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (photo.weightAtPhotoKg != null)
                    Text(
                      '⚖ ${photo.weightAtPhotoKg!.toStringAsFixed(1)} kg',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  if (photo.notes != null)
                    Text(photo.notes!,
                        style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Foto löschen?'),
            content: const Text(
                'Das verschlüsselte Foto wird unwiderruflich gelöscht.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Abbrechen')),
              FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(ctx).colorScheme.error),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Löschen')),
            ],
          ),
        ) ??
        false;
    if (ok && context.mounted) {
      await ref.read(photoOpsProvider.notifier).deletePhoto(photo);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

// ── Before / After comparison slider ─────────────────────────────────────────

class _BeforeAfterScreen extends ConsumerStatefulWidget {
  final List<BodyPhoto> photos;
  const _BeforeAfterScreen({required this.photos});

  @override
  ConsumerState<_BeforeAfterScreen> createState() => _BeforeAfterScreenState();
}

class _BeforeAfterScreenState extends ConsumerState<_BeforeAfterScreen> {
  int _beforeIdx = 0;
  int _afterIdx = 1;
  Uint8List? _beforeBytes;
  Uint8List? _afterBytes;
  double _sliderPos = 0.5;

  @override
  void initState() {
    super.initState();
    _afterIdx = widget.photos.length - 1;
    _loadBoth();
  }

  Future<void> _loadBoth() async {
    final ops = ref.read(photoOpsProvider.notifier);
    final b = await ops.loadPhotoBytes(widget.photos[_beforeIdx]);
    final a = await ops.loadPhotoBytes(widget.photos[_afterIdx]);
    if (mounted) setState(() { _beforeBytes = b; _afterBytes = a; });
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd('de_DE');
    final before = widget.photos[_beforeIdx];
    final after = widget.photos[_afterIdx];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Vorher / Nachher'),
      ),
      body: Column(
        children: [
          // Photo picker row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: _PhotoPickerBtn(
                    label: 'Vorher',
                    date: fmt.format(before.takenAt),
                    onTap: () => _pickPhoto(isBeforeSlot: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PhotoPickerBtn(
                    label: 'Nachher',
                    date: fmt.format(after.takenAt),
                    onTap: () => _pickPhoto(isBeforeSlot: false),
                  ),
                ),
              ],
            ),
          ),
          // Comparison view
          Expanded(
            child: (_beforeBytes == null || _afterBytes == null)
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : GestureDetector(
                    onHorizontalDragUpdate: (d) {
                      final box = context.findRenderObject() as RenderBox;
                      setState(() {
                        _sliderPos =
                            (_sliderPos + d.delta.dx / box.size.width)
                                .clamp(0.05, 0.95);
                      });
                    },
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final w = constraints.maxWidth;
                        final h = constraints.maxHeight;
                        return Stack(
                          children: [
                            // After (full)
                            SizedBox(
                              width: w,
                              height: h,
                              child: Image.memory(_afterBytes!,
                                  fit: BoxFit.contain),
                            ),
                            // Before (clipped left side)
                            ClipRect(
                              clipper: _LeftClipper(_sliderPos * w),
                              child: SizedBox(
                                width: w,
                                height: h,
                                child: Image.memory(_beforeBytes!,
                                    fit: BoxFit.contain),
                              ),
                            ),
                            // Divider line
                            Positioned(
                              left: _sliderPos * w - 1,
                              top: 0,
                              bottom: 0,
                              child: Container(width: 2, color: Colors.white),
                            ),
                            // Handle
                            Positioned(
                              left: _sliderPos * w - 16,
                              top: h / 2 - 16,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.compare_arrows,
                                    size: 18, color: Colors.black),
                              ),
                            ),
                            // Labels
                            Positioned(
                              left: 8,
                              top: 8,
                              child: _Label('Vorher'),
                            ),
                            Positioned(
                              right: 8,
                              top: 8,
                              child: _Label('Nachher'),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto({required bool isBeforeSlot}) async {
    final photos = widget.photos;
    final chosen = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(isBeforeSlot ? 'Vorher wählen' : 'Nachher wählen'),
        children: List.generate(photos.length, (i) {
          final p = photos[i];
          return SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(i),
            child: Text(
              '${DateFormat.yMMMd('de_DE').format(p.takenAt)} · ${_typeLabel(p.photoType)}',
            ),
          );
        }),
      ),
    );
    if (chosen == null) return;
    if (isBeforeSlot) {
      setState(() { _beforeIdx = chosen; _beforeBytes = null; });
    } else {
      setState(() { _afterIdx = chosen; _afterBytes = null; });
    }
    _loadBoth();
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  final double splitX;
  const _LeftClipper(this.splitX);

  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, 0, splitX, size.height);

  @override
  bool shouldReclip(_LeftClipper old) => old.splitX != splitX;
}

class _PhotoPickerBtn extends StatelessWidget {
  final String label;
  final String date;
  final VoidCallback onTap;
  const _PhotoPickerBtn(
      {required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white38),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 12)),
            Text(date,
                style: const TextStyle(fontSize: 11, color: Colors.white70)),
          ],
        ),
      );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      );
}
