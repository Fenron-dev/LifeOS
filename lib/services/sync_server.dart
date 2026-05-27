import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';

/// Shelf-based HTTP sync server. Runs on Desktop (the "hub") so that Android
/// clients can push/pull item events over the local Wi-Fi network.
///
/// Authentication: every request must include `Authorization: Bearer <psk>`.
/// PSK is a user-visible token generated once and stored in secure storage.
class SyncServer {
  final AppDatabase db;
  final String psk;
  final int port;
  final String deviceId;

  HttpServer? _server;

  SyncServer({
    required this.db,
    required this.psk,
    required this.port,
    required this.deviceId,
  });

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    final pipeline = const Pipeline()
        .addMiddleware(_pskMiddleware())
        .addMiddleware(logRequests())
        .addHandler(_router.call);
    _server = await shelf_io.serve(pipeline, InternetAddress.anyIPv4, port);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Middleware _pskMiddleware() => (Handler inner) {
        return (Request request) {
          if (request.url.path == 'api/v1/ping') return inner(request);
          final auth = request.headers['authorization'] ?? '';
          final token = auth.startsWith('Bearer ') ? auth.substring(7) : '';
          if (token != psk) {
            return Response(401, body: '{"error":"unauthorized"}',
                headers: {'content-type': 'application/json'});
          }
          return inner(request);
        };
      };

  Router get _router {
    final r = Router();

    r.get('/api/v1/ping', (Request req) => Response.ok(
        jsonEncode({'status': 'ok', 'device': deviceId}),
        headers: {'content-type': 'application/json'}));

    // Pull: GET /api/v1/events?since=<iso>&device_id=<id>
    r.get('/api/v1/events', (Request req) async {
      final sinceStr = req.url.queryParameters['since'];
      final requestingDevice = req.url.queryParameters['device_id'] ?? '';
      final since = sinceStr != null
          ? DateTime.tryParse(sinceStr) ?? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(0);

      final events = await db.getItemEventsSince(since,
          excludeDeviceId: requestingDevice.isEmpty ? null : requestingDevice);
      final json = events.map(eventToJson).toList();
      return Response.ok(jsonEncode(json),
          headers: {'content-type': 'application/json'});
    });

    // Push: POST /api/v1/events  body: [{event}, ...]
    r.post('/api/v1/events', (Request req) async {
      final body = await req.readAsString();
      final List<dynamic> list;
      try {
        list = jsonDecode(body) as List<dynamic>;
      } catch (_) {
        return Response(400, body: '{"error":"invalid json"}',
            headers: {'content-type': 'application/json'});
      }
      final companions = list
          .whereType<Map<String, dynamic>>()
          .map(SyncServer.jsonToCompanion)
          .toList();
      await db.insertSyncedEvents(companions);
      return Response.ok(
          jsonEncode({'inserted': companions.length}),
          headers: {'content-type': 'application/json'});
    });

    return r;
  }

  static Map<String, dynamic> eventToJson(ItemEvent e) => {
        'id': e.id,
        'type': e.type,
        'item_id': e.itemId,
        if (e.inventoryEntryId != null) 'inventory_entry_id': e.inventoryEntryId,
        if (e.quantity != null) 'quantity': e.quantity,
        if (e.unit != null) 'unit': e.unit,
        if (e.price != null) 'price': e.price,
        if (e.store != null) 'store': e.store,
        if (e.fromLocationId != null) 'from_location_id': e.fromLocationId,
        if (e.toLocationId != null) 'to_location_id': e.toLocationId,
        if (e.fromState != null) 'from_state': e.fromState,
        if (e.toState != null) 'to_state': e.toState,
        if (e.containerId != null) 'container_id': e.containerId,
        if (e.consumptionReason != null) 'consumption_reason': e.consumptionReason,
        if (e.thumbRating != null) 'thumb_rating': e.thumbRating,
        'device_id': e.deviceId,
        'sync_status': e.syncStatus,
        if (e.syncedAt != null) 'synced_at': e.syncedAt!.toIso8601String(),
        if (e.notes != null) 'notes': e.notes,
        'created_at': e.createdAt.toIso8601String(),
      };

  static ItemEventsCompanion jsonToCompanion(Map<String, dynamic> j) {
    return ItemEventsCompanion.insert(
      id: j['id'] as String? ?? const Uuid().v4(),
      type: j['type'] as String? ?? 'unknown',
      itemId: j['item_id'] as String? ?? '',
      inventoryEntryId: Value(j['inventory_entry_id'] as String?),
      quantity: Value((j['quantity'] as num?)?.toDouble()),
      unit: Value(j['unit'] as String?),
      price: Value((j['price'] as num?)?.toDouble()),
      store: Value(j['store'] as String?),
      fromLocationId: Value(j['from_location_id'] as String?),
      toLocationId: Value(j['to_location_id'] as String?),
      fromState: Value(j['from_state'] as String?),
      toState: Value(j['to_state'] as String?),
      containerId: Value(j['container_id'] as String?),
      consumptionReason: Value(j['consumption_reason'] as String?),
      thumbRating: Value(j['thumb_rating'] as String?),
      deviceId: j['device_id'] as String? ?? 'unknown',
      syncStatus: const Value('synced'),
      syncedAt: Value(DateTime.now()),
      notes: Value(j['notes'] as String?),
      createdAt:
          Value(DateTime.tryParse(j['created_at'] as String? ?? '') ??
              DateTime.now()),
    );
  }
}
