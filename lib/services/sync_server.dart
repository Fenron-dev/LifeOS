import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import 'sync_auth.dart';

/// Shelf-based HTTP sync server. Runs on Desktop (the "hub") so that Android
/// clients can push/pull item events and master data over the local network.
///
/// Authentication (S1): every request must carry an HMAC-SHA256 signature
/// over `timestamp\nmethod\npath\nbody` (see [SyncAuth]) — the PSK itself is
/// never transmitted. Brute-force attempts are rate-limited per IP (S3),
/// signature comparison is constant-time (S4) and bodies above
/// [maxBodyBytes] are rejected (S6).
class SyncServer {
  static const maxBodyBytes = 10 * 1024 * 1024; // 10 MB

  final AppDatabase db;
  final String psk;
  final int port;
  final String deviceId;

  HttpServer? _server;
  final _rateLimiter = SyncRateLimiter();

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
        .addMiddleware(_authMiddleware())
        .addHandler(_router.call);
    _server = await shelf_io.serve(pipeline, InternetAddress.anyIPv4, port);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  static String _clientIp(Request request) {
    final info = request.context['shelf.io.connection_info']
        as HttpConnectionInfo?;
    return info?.remoteAddress.address ?? 'unknown';
  }

  /// Reads the body once, enforces the size limit and verifies the HMAC
  /// signature. The body is handed to the route handlers via the request
  /// context (a shelf body can only be read once).
  Middleware _authMiddleware() => (Handler inner) {
        return (Request request) async {
          if (request.url.path == 'api/v1/ping') return inner(request);

          final ip = _clientIp(request);
          if (_rateLimiter.isLocked(ip)) {
            return Response(429,
                body: '{"error":"too many attempts"}',
                headers: {'content-type': 'application/json'});
          }

          final declaredLength = request.contentLength;
          if (declaredLength != null && declaredLength > maxBodyBytes) {
            return Response(413,
                body: '{"error":"payload too large"}',
                headers: {'content-type': 'application/json'});
          }
          final body = await request.readAsString();
          if (body.length > maxBodyBytes) {
            return Response(413,
                body: '{"error":"payload too large"}',
                headers: {'content-type': 'application/json'});
          }

          final ok = SyncAuth.verify(
            psk: psk,
            timestamp: request.headers[SyncAuth.timestampHeader],
            signature: request.headers[SyncAuth.signatureHeader],
            method: request.method,
            path: '/${request.url.path}',
            body: body,
          );
          if (!ok) {
            _rateLimiter.registerFailure(ip);
            return Response(401,
                body: '{"error":"unauthorized"}',
                headers: {'content-type': 'application/json'});
          }
          _rateLimiter.registerSuccess(ip);
          return inner(request.change(context: {'sync.body': body}));
        };
      };

  static String _bodyOf(Request req) =>
      req.context['sync.body'] as String? ?? '';

  Router get _router {
    final r = Router();
    Response json(Object data, {int status = 200}) => Response(status,
        body: jsonEncode(data),
        headers: {'content-type': 'application/json'});

    r.get('/api/v1/ping',
        (Request req) => json({'status': 'ok', 'device': deviceId}));

    // Pull events: GET /api/v1/events?since=<iso>&device_id=<id>
    r.get('/api/v1/events', (Request req) async {
      final since = DateTime.tryParse(
              req.url.queryParameters['since'] ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final requestingDevice = req.url.queryParameters['device_id'] ?? '';
      final events = await db.getItemEventsSince(since,
          excludeDeviceId: requestingDevice.isEmpty ? null : requestingDevice);
      return json(events.map(eventToJson).toList());
    });

    // Push events: POST /api/v1/events  body: [{event}, ...]
    r.post('/api/v1/events', (Request req) async {
      final List<dynamic> list;
      try {
        list = jsonDecode(_bodyOf(req)) as List<dynamic>;
      } catch (_) {
        return json({'error': 'invalid json'}, status: 400);
      }
      final companions = list
          .whereType<Map<String, dynamic>>()
          .map(SyncServer.jsonToCompanion)
          .toList();
      final inserted = await db.ingestForeignEvents(companions);
      return json({'inserted': inserted});
    });

    // Pull master data: GET /api/v1/entities?since=<iso>
    r.get('/api/v1/entities', (Request req) async {
      final since = DateTime.tryParse(
              req.url.queryParameters['since'] ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return json(await db.masterDataSince(since));
    });

    // Push master data: POST /api/v1/entities
    r.post('/api/v1/entities', (Request req) async {
      final Map<String, dynamic> data;
      try {
        data = jsonDecode(_bodyOf(req)) as Map<String, dynamic>;
      } catch (_) {
        return json({'error': 'invalid json'}, status: 400);
      }
      final applied = await db.applyMasterData(data);
      return json({'applied': applied});
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
