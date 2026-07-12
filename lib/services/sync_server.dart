import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

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

    // Pull the full vault dump: GET /api/v1/full
    r.get('/api/v1/full', (Request req) async {
      return json({'version': 1, 'tables': await db.exportForSync()});
    });

    // Push a full vault dump: POST /api/v1/full  body: {version, tables}
    r.post('/api/v1/full', (Request req) async {
      final Map<String, dynamic> body;
      try {
        body = jsonDecode(_bodyOf(req)) as Map<String, dynamic>;
      } catch (_) {
        return json({'error': 'invalid json'}, status: 400);
      }
      final tables = body['tables'];
      if (tables is! Map) {
        return json({'error': 'missing tables'}, status: 400);
      }
      final applied =
          await db.importFromSync(Map<String, dynamic>.from(tables));
      return json({'applied': applied});
    });

    return r;
  }
}
