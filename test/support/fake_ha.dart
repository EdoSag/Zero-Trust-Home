import 'dart:async';

import 'package:zerotrust_home/adapters/homeassistant/ha_client.dart';

/// A Home Assistant that lives in memory and speaks its WebSocket API.
class FakeHa {
  FakeHa({this.token = 'good-token', List<Map<String, dynamic>>? states}) {
    for (final s in states ?? const <Map<String, dynamic>>[]) {
      this.states[s['entity_id'] as String] = s;
    }
  }

  String token;
  final states = <String, Map<String, dynamic>>{};

  /// Service calls received: (domain, service, entity, data).
  final calls = <(String, String, String, Map<String, dynamic>)>[];
  final uris = <Uri>[];
  final sockets = <FakeHaSocket>[];

  /// Nothing listens at the address.
  bool down = false;

  /// What answers isn't Home Assistant: no greeting.
  bool silent = false;

  /// Signs in, then refuses to list states.
  bool failStates = false;

  int get open => sockets.where((s) => !s.closed).length;

  Future<HaSocket> connect(Uri uri) async {
    uris.add(uri);
    if (down) throw const HaException(HaFailure.unreachable, 'refused');
    final socket = FakeHaSocket(this);
    sockets.add(socket);
    if (!silent) {
      scheduleMicrotask(() => socket._out({'type': 'auth_required'}));
    }
    return socket;
  }

  /// Changes an entity as if someone used it, and tells subscribers.
  void change(String entity, String state, [Map<String, dynamic>? attributes]) {
    final now = {
      'entity_id': entity,
      'state': state,
      'attributes': attributes ?? states[entity]?['attributes'] ?? const {},
    };
    states[entity] = now;
    for (final s in sockets) {
      s._changed(entity, now);
    }
  }

  /// Drops every connection, as when Home Assistant restarts.
  void restart() {
    for (final s in [...sockets]) {
      s._drop();
    }
  }
}

class FakeHaSocket implements HaSocket {
  FakeHaSocket(this.ha);
  final FakeHa ha;
  final _messages = StreamController<Map<String, dynamic>>();
  var closed = false;
  var _signedIn = false;
  int? _subscription;

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;

  void _out(Map<String, dynamic> m) {
    if (!closed) _messages.add(m);
  }

  void _changed(String entity, Map<String, dynamic> state) {
    final id = _subscription;
    if (id == null || closed) return;
    _out({
      'id': id,
      'type': 'event',
      'event': {
        'event_type': 'state_changed',
        'data': {'entity_id': entity, 'new_state': state},
      },
    });
  }

  void _drop() {
    if (closed) return;
    closed = true;
    _messages.close();
  }

  @override
  void send(Map<String, dynamic> m) {
    scheduleMicrotask(() => _handle(m));
  }

  void _handle(Map<String, dynamic> m) {
    if (closed) return;
    final id = m['id'];
    void ok([Object? result]) =>
        _out({'id': id, 'type': 'result', 'success': true, 'result': result});
    switch (m['type']) {
      case 'auth':
        if (m['access_token'] == ha.token) {
          _signedIn = true;
          _out({'type': 'auth_ok'});
        } else {
          _out({'type': 'auth_invalid', 'message': 'Invalid access token'});
          _drop();
        }
      case _ when !_signedIn:
        _drop();
      case 'get_states' when ha.failStates:
        _out({
          'id': id,
          'type': 'result',
          'success': false,
          'error': {'code': 'unknown_error', 'message': 'Busy'},
        });
      case 'get_states':
        ok([...ha.states.values]);
      case 'subscribe_events':
        _subscription = id as int;
        ok();
      case 'call_service':
        final entity = (m['target'] as Map)['entity_id'] as String;
        if (!ha.states.containsKey(entity)) {
          _out({
            'id': id,
            'type': 'result',
            'success': false,
            'error': {'code': 'not_found', 'message': 'Entity not found'},
          });
          return;
        }
        ha.calls.add((
          m['domain'] as String,
          m['service'] as String,
          entity,
          Map<String, dynamic>.from(m['service_data'] as Map),
        ));
        ok();
    }
  }

  @override
  Future<void> close() async => _drop();
}

Map<String, dynamic> haState(
  String entity,
  String state, [
  Map<String, dynamic> attributes = const {},
]) => {'entity_id': entity, 'state': state, 'attributes': attributes};
