import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import 'vault_provider.dart';

final eventsForItemProvider =
    StreamProvider.family<List<ItemEvent>, String>((ref, itemId) {
  final db = ref.watch(databaseProvider);
  if (db == null) return const Stream.empty();
  return db.watchEventsForItem(itemId);
});
