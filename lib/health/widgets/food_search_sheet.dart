import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../db/database.dart';
import '../../providers/vault_provider.dart';
import '../../services/open_food_facts_service.dart';

/// The result of picking a product in [FoodSearchSheet].
/// Carries all nutritional metadata (per 100 g) plus display fields.
class FoodSearchResult {
  final String productName;
  final String? brand;
  final String? ean;
  final String? itemId; // non-null when picked from local inventory
  final double? caloriesPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;
  final double? fiberPer100g;
  final double? servingSizeG;
  final String source; // 'local' | 'off' | 'manual'

  const FoodSearchResult({
    required this.productName,
    this.brand,
    this.ean,
    this.itemId,
    this.caloriesPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
    this.fiberPer100g,
    this.servingSizeG,
    required this.source,
  });
}

/// Bottom sheet for searching food products. Queries both the vault's local
/// item catalogue and the OpenFoodFacts API in parallel. Pops with a
/// [FoodSearchResult] when the user taps a result, or `null` on cancel.
class FoodSearchSheet extends ConsumerStatefulWidget {
  const FoodSearchSheet({super.key});

  @override
  ConsumerState<FoodSearchSheet> createState() => _FoodSearchSheetState();
}

class _FoodSearchSheetState extends ConsumerState<FoodSearchSheet> {
  final _controller = TextEditingController();

  bool _loading = false;
  List<_SearchItem> _results = [];
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = ref.read(databaseProvider);
      final futures = await Future.wait([
        _searchLocal(db, q),
        OpenFoodFactsService.searchByName(q, pageSize: 20),
      ]);

      final localItems = futures[0] as List<_SearchItem>;
      final offProducts = futures[1] as List<OFFProduct>;

      final offItems = offProducts
          .map((p) => _SearchItem.fromOff(p))
          .toList();

      // Local results first, then OFF — deduplicate by EAN.
      final seen = <String>{};
      final merged = <_SearchItem>[];
      for (final item in [...localItems, ...offItems]) {
        final key = item.ean ?? '${item.source}:${item.name}';
        if (seen.add(key)) merged.add(item);
      }

      setState(() {
        _results = merged;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Suche fehlgeschlagen';
        _loading = false;
      });
    }
  }

  Future<List<_SearchItem>> _searchLocal(AppDatabase? db, String q) async {
    if (db == null) return [];
    // searchItems returns a stream; .first gives the current snapshot.
    final rows = await db.searchItems(q).first;
    return rows.map(_SearchItem.fromItem).toList();
  }

  void _pick(_SearchItem item) {
    Navigator.of(context).pop(FoodSearchResult(
      productName: item.name,
      brand: item.brand,
      ean: item.ean,
      itemId: item.itemId,
      caloriesPer100g: item.caloriesPer100g,
      proteinPer100g: item.proteinPer100g,
      carbsPer100g: item.carbsPer100g,
      fatPer100g: item.fatPer100g,
      fiberPer100g: item.fiberPer100g,
      servingSizeG: item.servingSizeG,
      source: item.source,
    ));
  }

  void _pickManual() {
    final name = _controller.text.trim();
    Navigator.of(context).pop(FoodSearchResult(
      productName: name.isEmpty ? 'Manueller Eintrag' : name,
      source: 'manual',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Text('Lebensmittel suchen',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    child: const Text('Abbrechen'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Name oder EAN …',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: _search,
                textInputAction: TextInputAction.search,
              ),
            ),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!,
                    style: TextStyle(color: cs.error)),
              ),
            Expanded(
              child: _results.isEmpty && !_loading
                  ? _EmptyHint(
                      hasQuery: _controller.text.trim().isNotEmpty,
                      onManual: _pickManual,
                    )
                  : ListView.builder(
                      itemCount: _results.length + 1,
                      itemBuilder: (ctx, i) {
                        if (i == _results.length) {
                          return ListTile(
                            leading: const Icon(Icons.edit_outlined),
                            title: const Text('Manuell eingeben'),
                            onTap: _pickManual,
                          );
                        }
                        final item = _results[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                item.source == 'local'
                                    ? cs.primaryContainer
                                    : cs.secondaryContainer,
                            child: Icon(
                              item.source == 'local'
                                  ? Icons.inventory_2_outlined
                                  : Icons.public,
                              size: 18,
                              color: item.source == 'local'
                                  ? cs.onPrimaryContainer
                                  : cs.onSecondaryContainer,
                            ),
                          ),
                          title: Text(item.name),
                          subtitle: Text(
                            [
                              if (item.brand != null) item.brand!,
                              if (item.caloriesPer100g != null)
                                '${item.caloriesPer100g!.toStringAsFixed(0)} kcal/100g',
                            ].join(' · '),
                            style:
                                TextStyle(color: cs.onSurfaceVariant),
                          ),
                          onTap: () => _pick(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final bool hasQuery;
  final VoidCallback onManual;
  const _EmptyHint({required this.hasQuery, required this.onManual});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search,
                size: 48,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              hasQuery
                  ? 'Keine Ergebnisse — Suche starten oder manuell eingeben.'
                  : 'Produktname eintippen und Enter drücken.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            if (hasQuery) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onManual,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Manuell eingeben'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Internal search result wrapper ──────────────────────────────────────────

class _SearchItem {
  final String name;
  final String? brand;
  final String? ean;
  final String? itemId;
  final double? caloriesPer100g;
  final double? proteinPer100g;
  final double? carbsPer100g;
  final double? fatPer100g;
  final double? fiberPer100g;
  final double? servingSizeG;
  final String source; // 'local' | 'off'

  const _SearchItem({
    required this.name,
    this.brand,
    this.ean,
    this.itemId,
    this.caloriesPer100g,
    this.proteinPer100g,
    this.carbsPer100g,
    this.fatPer100g,
    this.fiberPer100g,
    this.servingSizeG,
    required this.source,
  });

  factory _SearchItem.fromItem(Item item) => _SearchItem(
        name: item.name,
        brand: item.brand,
        ean: item.ean,
        itemId: item.id,
        caloriesPer100g: item.caloriesPer100g,
        proteinPer100g: item.proteinPer100g,
        carbsPer100g: item.carbsPer100g,
        fatPer100g: item.fatPer100g,
        fiberPer100g: item.fiberPer100g,
        source: 'local',
      );

  factory _SearchItem.fromOff(OFFProduct p) => _SearchItem(
        name: p.name ?? p.ean,
        brand: p.brand,
        ean: p.ean,
        caloriesPer100g: p.calories,
        proteinPer100g: p.protein,
        carbsPer100g: p.carbs,
        fatPer100g: p.fat,
        fiberPer100g: p.fiber,
        servingSizeG: p.servingSizeG,
        source: 'off',
      );
}
