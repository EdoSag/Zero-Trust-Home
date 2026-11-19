import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Why talking to Home Assistant failed.
enum HaFailure {
  /// Nothing answered at that address, or the connection dropped.
  unreachable,

  /// Home Assistant refused the token.
  badToken,

  /// Something answered, but it isn't Home Assistant's API.
  notHomeAssistant,

  /// Home Assistant refused the request.
  failed,
}

class HaException implements Exception {
  const HaException(this.failure, [this.detail = '']);
  final HaFailure failure;
  final String detail;
  @override
  String toString() => 'HaException(${failure.name}: $detail)';
}

/// One JSON message connection. The real one is a WebSocket; tests give
/// their own.
abstract class HaSocket {
  /// Every message received, until the connection closes.
  Stream<Map<String, dynamic>> get messages;
  void send(Map<String, dynamic> message);
  Future<void> close();
}

typedef HaConnect = Future<HaSocket> Function(Uri uri);

/// Opens a WebSocket. Plain `ws://` works: Home Assistant on a home
/// network usually has no certificate.
Future<HaSocket> connectWebSocket(Uri uri) async {
  try {
    final socket = await WebSocket.connect(
      uri.toString(),
    ).timeout(const Duration(seconds: 10));
    socket.pingInterval = const Duration(seconds: 30);
    return _WebSocketHaSocket(socket);
  } on Object catch (e) {
    throw HaException(HaFailure.unreachable, '$e');
  }
}

class _WebSocketHaSocket implements HaSocket {
  _WebSocketHaSocket(this._socket);
  final WebSocket _socket;

  @override
  late final Stream<Map<String, dynamic>> messages = _socket
      .where((m) => m is String)
      .map((m) => jsonDecode(m as String))
      .where((m) => m is Map)
      .map((m) => Map<String, dynamic>.from(m as Map));

  @override
  void send(Map<String, dynamic> message) => _socket.add(jsonEncode(message));

  @override
  Future<void> close() => _socket.close();
}

/// An entity's state as Home Assistant reports it.
typedef HaState = Map<String, dynamic>;

/// A signed-in connection to Home Assistant's WebSocket API.
class HaClient {
  HaClient._(this._socket);
  final HaSocket _socket;

  var _nextId = 1;
  final _pending = <int, Completer<Object?>>{};
  final _changes = StreamController<(String, HaState?)>.broadcast();
  final _closed = Completer<void>();
  StreamSubscription<Map<String, dynamic>>? _subscription;
  int? _changesId;

  static const timeout = Duration(seconds: 15);

  /// Signs in with [token]. Throws [HaException].
  static Future<HaClient> connect(
    HaConnect connect,
    Uri uri,
    String token,
  ) async {
    final socket = await connect(uri);
    final client = HaClient._(socket);
    try {
      await client._signIn(token);
    } on Object {
      await client.close();
      rethrow;
    }
    return client;
  }

  Future<void> _signIn(String token) async {
    final signedIn = Completer<void>();
    _subscription = _socket.messages.listen(
      (m) {
        switch (m['type']) {
          case 'auth_required':
            _socket.send({'type': 'auth', 'access_token': token});
          case 'auth_ok':
            if (!signedIn.isCompleted) signedIn.complete();
          case 'auth_invalid':
            if (!signedIn.isCompleted) {
              signedIn.completeError(
                HaException(HaFailure.badToken, '${m['message'] ?? ''}'),
              );
            }
          case 'result':
            _answer(m);
          case 'event':
            _event(m);
        }
      },
      onError: (Object e) => _end(),
      onDone: _end,
      cancelOnError: true,
    );
    _closed.future.then((_) {
      if (!signedIn.isCompleted) {
        signedIn.completeError(
          const HaException(HaFailure.notHomeAssistant, 'closed'),
        );
      }
    }).ignore();
    await signedIn.future.timeout(
      timeout,
      onTimeout: () =>
          throw const HaException(HaFailure.notHomeAssistant, 'no answer'),
    );
  }

  void _answer(Map<String, dynamic> m) {
    final id = m['id'];
    final waiting = id is int ? _pending.remove(id) : null;
    if (waiting == null) return;
    if (m['success'] == true) {
      waiting.complete(m['result']);
    } else {
      final error = m['error'];
      waiting.completeError(
        HaException(
          HaFailure.failed,
          error is Map ? '${error['message'] ?? error['code']}' : '',
        ),
      );
    }
  }

  void _event(Map<String, dynamic> m) {
    if (m['id'] != _changesId) return;
    final event = m['event'];
    if (event is! Map) return;
    final data = event['data'];
    if (data is! Map) return;
    final entity = data['entity_id'];
    if (entity is! String) return;
    final state = data['new_state'];
    _changes.add((
      entity,
      state is Map ? Map<String, dynamic>.from(state) : null,
    ));
  }

  void _end() {
    if (_closed.isCompleted) return;
    _closed.complete();
    for (final waiting in _pending.values) {
      waiting.completeError(const HaException(HaFailure.unreachable, 'closed'));
    }
    _pending.clear();
    _changes.close();
  }

  /// Completes when the connection is gone.
  Future<void> get done => _closed.future;
  bool get isClosed => _closed.isCompleted;

  Future<Object?> _request(Map<String, dynamic> message) {
    if (isClosed) {
      return Future.error(const HaException(HaFailure.unreachable, 'closed'));
    }
    final id = _nextId++;
    final answer = Completer<Object?>();
    _pending[id] = answer;
    _socket.send({...message, 'id': id});
    return answer.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw const HaException(HaFailure.unreachable, 'no answer');
      },
    );
  }

  /// Every entity's state now.
  Future<List<HaState>> states() async {
    final result = await _request({'type': 'get_states'});
    return [
      for (final s in result as List? ?? const [])
        if (s is Map) Map<String, dynamic>.from(s),
    ];
  }

  /// Each entity whose state changes, with its new state (null when it was
  /// removed). Starts the subscription on the first call.
  Future<Stream<(String, HaState?)>> changes() async {
    if (_changesId == null) {
      final id = _nextId;
      _changesId = id;
      try {
        await _request({
          'type': 'subscribe_events',
          'event_type': 'state_changed',
        });
      } on Object {
        _changesId = null;
        rethrow;
      }
    }
    return _changes.stream;
  }

  Future<void> callService(
    String domain,
    String service,
    String entityId, [
    Map<String, dynamic> data = const {},
  ]) => _request({
    'type': 'call_service',
    'domain': domain,
    'service': service,
    'service_data': data,
    'target': {'entity_id': entityId},
  });

  /// Doesn't wait for the server to agree: one that is gone never would.
  Future<void> close() async {
    _end();
    _subscription?.cancel().ignore();
    _socket.close().ignore();
  }
}
