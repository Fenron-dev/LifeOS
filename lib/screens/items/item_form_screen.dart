import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../db/database.dart';
import '../../providers/items_provider.dart';
import '../../services/open_food_facts_service.dart';

/// Create or edit an item.
/// Pass [itemId] for edit mode (loaded internally), null for create.
/// Pass [prefillEan] when coming from a barcode scan.
class ItemFormScreen extends ConsumerWidget {
  final String? itemId;
  final Item? item;
  final String? prefillEan;

  const ItemFormScreen({super.key, this.itemId, this.item, this.prefillEan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // If we have the item directly, show the form immediately.
    if (item != null || itemId == null) {
      return _ItemFormBody(item: item, prefillEan: prefillEan);
    }
    // Otherwise load by id.
    final itemAsync = ref.watch(itemByIdProvider(itemId!));
    return itemAsync.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Fehler: $e'))),
      data: (loaded) => _ItemFormBody(item: loaded, prefillEan: prefillEan),
    );
  }
}

class _ItemFormBody extends ConsumerStatefulWidget {
  final Item? item;
  final String? prefillEan;

  const _ItemFormBody({this.item, this.prefillEan});

  @override
  ConsumerState<_ItemFormBody> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends ConsumerState<_ItemFormBody> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _brandCtrl;
  late final TextEditingController _eanCtrl;
  late final TextEditingController _notesCtrl;

  String _productType = 'needsCooking';
  bool _alwaysConsumedFully = false;
  bool _openedFlag = true;
  String _categoryId = 'food';
  bool _loadingOff = false;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _nameCtrl = TextEditingController(text: i?.name ?? '');
    _brandCtrl = TextEditingController(text: i?.brand ?? '');
    _eanCtrl = TextEditingController(text: i?.ean ?? widget.prefillEan ?? '');
    _notesCtrl = TextEditingController(text: i?.notes ?? '');
    if (i != null) {
      _productType = i.productType;
      _alwaysConsumedFully = i.alwaysConsumedFully;
      _openedFlag = i.openedFlag;
      _categoryId = i.categoryId;
    }
    // Auto-lookup if EAN was scanned
    if (widget.prefillEan != null && widget.item == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookupOff());
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _eanCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _lookupOff() async {
    final ean = _eanCtrl.text.trim();
    if (ean.isEmpty) return;
    setState(() => _loadingOff = true);
    final product = await OpenFoodFactsService.lookup(ean);
    if (!mounted) return;
    setState(() => _loadingOff = false);
    if (product == null) return;
    if (product.name.isNotEmpty && _nameCtrl.text.isEmpty) {
      _nameCtrl.text = product.name;
    }
    if (product.brand != null && _brandCtrl.text.isEmpty) {
      _brandCtrl.text = product.brand!;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final notifier = ref.read(itemsNotifierProvider.notifier);
    final existing = widget.item;
    if (existing == null) {
      await notifier.createItem(
        name: _nameCtrl.text.trim(),
        brand: _brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim(),
        ean: _eanCtrl.text.trim().isEmpty ? null : _eanCtrl.text.trim(),
        categoryId: _categoryId,
        productType: _productType,
        alwaysConsumedFully: _alwaysConsumedFully,
        openedFlag: _openedFlag,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
    } else {
      await notifier.updateItem(existing.copyWith(
        name: _nameCtrl.text.trim(),
        brand: Value(_brandCtrl.text.trim().isEmpty ? null : _brandCtrl.text.trim()),
        ean: Value(_eanCtrl.text.trim().isEmpty ? null : _eanCtrl.text.trim()),
        categoryId: _categoryId,
        productType: _productType,
        alwaysConsumedFully: _alwaysConsumedFully,
        openedFlag: _openedFlag,
        notes: Value(_notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
        updatedAt: DateTime.now(),
      ));
    }
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.item != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Artikel bearbeiten' : 'Neuer Artikel'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Speichern'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // EAN + OFF-Lookup
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _eanCtrl,
                    decoration: const InputDecoration(
                      labelText: 'EAN / Barcode',
                      prefixIcon: Icon(Icons.barcode_reader),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: _loadingOff ? null : _lookupOff,
                  tooltip: 'OpenFoodFacts nachschlagen',
                  icon: _loadingOff
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Name
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Name *'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Name erforderlich' : null,
            ),
            const SizedBox(height: 12),
            // Brand
            TextFormField(
              controller: _brandCtrl,
              decoration: const InputDecoration(labelText: 'Marke'),
            ),
            const SizedBox(height: 16),
            // Category
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _categoryId,
              decoration: const InputDecoration(labelText: 'Kategorie'),
              items: const [
                DropdownMenuItem(value: 'food', child: Text('Lebensmittel')),
                DropdownMenuItem(value: 'appliance', child: Text('Gerät / Haushalt')),
                DropdownMenuItem(value: 'task', child: Text('Aufgabe')),
                DropdownMenuItem(value: 'wishlist', child: Text('Wunschliste')),
              ],
              onChanged: (v) => setState(() => _categoryId = v!),
            ),
            const SizedBox(height: 12),
            // Product type
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _productType,
              decoration: const InputDecoration(labelText: 'Produkttyp'),
              items: const [
                DropdownMenuItem(
                  value: 'readyToEat',
                  child: Text('Fertiggericht / Konserve / TK'),
                ),
                DropdownMenuItem(
                  value: 'needsCooking',
                  child: Text('Muss zubereitet werden'),
                ),
                DropdownMenuItem(
                  value: 'ingredient',
                  child: Text('Zutat / Gewürz'),
                ),
              ],
              onChanged: (v) => setState(() => _productType = v!),
            ),
            const SizedBox(height: 8),
            // Flags
            SwitchListTile(
              value: _alwaysConsumedFully,
              onChanged: (v) => setState(() => _alwaysConsumedFully = v),
              title: const Text('Immer komplett verbraucht'),
              subtitle: const Text('Beim Scan wird der gesamte Bestand abgezogen'),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              value: _openedFlag,
              onChanged: (v) => setState(() => _openedFlag = v),
              title: const Text('Bleibt nach Öffnen vorhanden'),
              subtitle: const Text('Für Mindestmengen: gilt als vorhanden bis leer'),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            // Notes
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Notizen'),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}
