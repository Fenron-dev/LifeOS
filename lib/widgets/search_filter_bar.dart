import 'package:flutter/material.dart';

/// Standardized search bar + filter button row with active-filter chip strip.
///
/// Usage pattern (copy-paste into any ConsumerStatefulWidget):
///
/// ```dart
/// // 1. Declare state:
/// String _query = '';
/// final _activeFilters = <String, String>{};
///
/// // 2. In AppBar bottom / body header:
/// SearchAndFilterBar(
///   query: _query,
///   onQueryChanged: (v) => setState(() => _query = v),
///   hasActiveFilters: _activeFilters.isNotEmpty,
///   activeFilterChips: _activeFilters.entries.map((e) =>
///     ActiveFilterChip(label: e.value, onRemove: () => setState(() => _activeFilters.remove(e.key)))).toList(),
///   onFilterTap: () => _openFilterSheet(context),
/// )
/// ```
class SearchAndFilterBar extends StatelessWidget {
  final String query;
  final ValueChanged<String> onQueryChanged;
  final String hintText;
  final bool hasActiveFilters;
  final List<ActiveFilterChip> activeFilterChips;
  final VoidCallback onFilterTap;
  final TextEditingController? controller;

  const SearchAndFilterBar({
    super.key,
    required this.query,
    required this.onQueryChanged,
    required this.onFilterTap,
    this.hintText = 'Suchen…',
    this.hasActiveFilters = false,
    this.activeFilterChips = const [],
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: SearchBar(
                  controller: controller,
                  hintText: hintText,
                  leading: const Icon(Icons.search),
                  trailing: [
                    if (query.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          controller?.clear();
                          onQueryChanged('');
                        },
                      ),
                  ],
                  onChanged: onQueryChanged,
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: hasActiveFilters,
                smallSize: 8,
                child: IconButton.filledTonal(
                  icon: const Icon(Icons.tune),
                  tooltip: 'Filtern',
                  onPressed: onFilterTap,
                ),
              ),
            ],
          ),
        ),
        if (activeFilterChips.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              children: activeFilterChips,
            ),
          ),
      ],
    );
  }
}

/// A single chip showing an active filter value with a red × remove button.
class ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;

  const ActiveFilterChip({
    super.key,
    required this.label,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Chip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        deleteIcon:
            Icon(Icons.close, size: 14, color: cs.error),
        onDeleted: onRemove,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: cs.primaryContainer,
        labelStyle: TextStyle(color: cs.onPrimaryContainer),
      ),
    );
  }
}
