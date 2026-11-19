import 'dart:async';

import '../../model/device.dart';
import '../device_adapter.dart';
import 'ha_client.dart';
import 'ha_entities.dart';
import 'ha_server.dart';

/// Where a Home Assistant entity is: its home's server and its entity id.
/// Saved as `HomeDevice.address`.
class HaAddress {
  const HaAddress(this.entityId);
  final String entityId;

  static HaAddress? parse(Map<String, dynamic> json) {
    final entity = json['entity'];
    return entity is String && entity.contains('.') ? HaAddress(entity) : null;
  }

  Map<String, dynamic> toJson() => {'entity': entityId};
}

/// Devices that Home Assistant already controls (thousands of brands and
/// protocols), through its local WebSocket API. One connection per home,
/// shared by all of the home's entities, open while any of them is on
/// screen. The token stays in the home's encrypted vault item.
class HomeAssistantAdapter implements DeviceAdapter {
  HomeAssistantAdapter({
    required this.loadServer,
    HaConnect? connect,
    this.linger = const Duration(seconds: 30),
    this.retryAfter = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(seconds: 60),
    ],
  }) : connect = connect ?? connectWebSocket;

  static const adapterId = 'homeassistant';

  /// The home's server, or null when it has none.
  final Future<HaServer?> Function(String homeId) loadServer;
  final HaConnect connect;

  /// How long a connection stays open after the last entity left the
  /// screen.
  final Duration linger;

  /// Pauses between attempts to reconnect, the last one repeated.
  final List<Duration> retryAfter;

  final _sessions = <String, _HaSession>{};
  var _disposed = false;

  @override
  String get id => adapterId;

  /// Signs in to [server] and lists what it has that the app can show.
  /// Throws [HaException].
  Future<List<HaEntity>> entities(HaServer server) async {
    final client = await HaClient.connect(
      connect,
      server.socketUri,
      server.token,
    );
    try {
      return [for (final s in await client.states()) ?HaEntity.from(s)]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } finally {
      await client.close();
    }
  }

  /// The device to save for [entity].
  HomeDevice deviceFor({
    required String id,
    required String homeId,
    required HaEntity entity,
    String? roomId,
  }) => HomeDevice(
    id: id,
    homeId: homeId,
    roomId: roomId,
    name: entity.name,
    type: entity.type,
    adapter: adapterId,
    address: HaAddress(entity.id).toJson(),
    capabilities: entity.capabilities,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );

  Future<_HaSession?> _session(String homeId) async {
    final server = await loadServer(homeId);
    if (server == null || _disposed) return null;
    final old = _sessions[homeId];
    if (old != null && old.server.signature == server.signature) return old;
    final next = _sessions[homeId] = _HaSession(this, server);
    if (old != null) {
      // New address or token: what is on screen moves to the new
      // connection rather than staying on the old one.
      next._listeners.addAll(old._listeners);
      old._listeners.clear();
      old.dispose();
      if (next._watched) next._start();
    }
    return next;
  }

  @override
  Stream<DeviceState> watch(HomeDevice device) {
    final address = HaAddress.parse(device.address);
    if (address == null) return Stream.value(const DeviceState.unreachable());
    late final StreamController<DeviceState> out;
    _HaSession? session;
    out = StreamController<DeviceState>(
      onListen: () async {
        session = await _session(device.homeId);
        if (out.isClosed) return;
        if (session == null) {
          out.add(const DeviceState.unreachable());
          return;
        }
        session!.listen(address.entityId, out);
      },
      onCancel: () {
        // The session may have been replaced since (a new token).
        _sessions[device.homeId]?.leave(address.entityId, out);
        session?.leave(address.entityId, out);
        return out.close();
      },
    );
    return out.stream;
  }

  @override
  Future<void> send(HomeDevice device, DeviceCommand command) async {
    final address = HaAddress.parse(device.address);
    if (address == null) {
      throw StateError('${device.name} isn\'t a Home Assistant entity');
    }
    final session = await _session(device.homeId);
    if (session == null) {
      throw const HaException(HaFailure.unreachable, 'No Home Assistant');
    }
    await session.send(address.entityId, command);
  }

  @override
  Future<void> forget(
    HomeDevice device, {
    required List<HomeDevice> others,
  }) async {
    // Nothing to tell Home Assistant: the entity stays there. The
    // connection closes once nothing of the home is left to watch.
    if (others.any((d) => d.homeId == device.homeId)) return;
    _sessions.remove(device.homeId)?.dispose();
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final s in _sessions.values.toList()) {
      s.dispose();
    }
    _sessions.clear();
  }
}

/// One home's connection: the latest state of each entity, and who is
/// watching which.
class _HaSession {
  _HaSession(this.adapter, this.server);
  final HomeAssistantAdapter adapter;
  final HaServer server;

  final _listeners = <String, List<StreamController<DeviceState>>>{};
  final _states = <String, HaState?>{};
  HaClient? _client;
  Future<HaClient>? _connecting;
  StreamSubscription<(String, HaState?)>? _changes;
  Timer? _retry;
  Timer? _idle;
  var _failures = 0;
  var _disposed = false;

  bool get _watched => _listeners.values.any((l) => l.isNotEmpty);

  void listen(String entity, StreamController<DeviceState> out) {
    _idle?.cancel();
    (_listeners[entity] ??= []).add(out);
    final client = _client;
    if (client != null && !client.isClosed) {
      out.add(haRead(_states[entity]));
    } else {
      _start();
    }
  }

  void leave(String entity, StreamController<DeviceState> out) {
    _listeners[entity]?.remove(out);
    if (!_watched) leaveAll();
  }

  void _emit(String entity) {
    final state = haRead(_states[entity]);
    for (final out in [...?_listeners[entity]]) {
      if (!out.isClosed) out.add(state);
    }
  }

  void _emitAll() {
    for (final entity in _listeners.keys) {
      _emit(entity);
    }
  }

  void _start() {
    if (_connecting != null || _disposed) return;
    _retry?.cancel();
    _connect().then((_) {}, onError: (Object _) {}).ignore();
  }

  Future<HaClient> _connect() {
    final client = _client;
    if (client != null && !client.isClosed) return Future.value(client);
    return _connecting ??= () async {
      HaClient? attempt;
      try {
        final client = attempt = await HaClient.connect(
          adapter.connect,
          server.socketUri,
          server.token,
        );
        if (_disposed) {
          throw const HaException(HaFailure.unreachable, 'closed');
        }
        final changes = await client.changes();
        final states = await client.states();
        _states
          ..clear()
          ..addAll({
            for (final s in states)
              if (s['entity_id'] is String) s['entity_id'] as String: s,
          });
        _changes = changes.listen((change) {
          _states[change.$1] = change.$2;
          _emit(change.$1);
        });
        _client = client;
        _failures = 0;
        client.done.then((_) => _dropped(client)).ignore();
        _emitAll();
        return client;
      } on Object {
        // Signed in but not set up: this connection is closed, not left
        // open beside the next attempt.
        attempt?.close().ignore();
        _states.clear();
        _failures++;
        _emitAll(); // As unreachable: there is no state now.
        _scheduleRetry();
        rethrow;
      } finally {
        _connecting = null;
      }
    }();
  }

  void _dropped(HaClient client) {
    if (_client != client) return;
    _client = null;
    _changes?.cancel();
    _changes = null;
    _states.clear();
    if (_disposed) return;
    _emitAll();
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_disposed || !_watched) return;
    final pauses = adapter.retryAfter;
    final pause = pauses[(_failures - 1).clamp(0, pauses.length - 1)];
    _retry?.cancel();
    _retry = Timer(pause, _start);
  }

  Future<void> send(String entity, DeviceCommand command) async {
    final client = await _connect();
    final call = haWrite(entity, command, _states[entity]);
    if (call == null) {
      throw StateError('$entity can\'t do ${command.capability.name}');
    }
    try {
      await client.callService(call.$1, call.$2, entity, call.$3);
    } finally {
      // Opened only for this (a widget, an automation): not kept open.
      if (!_watched) leaveAll();
    }
  }

  void leaveAll() {
    _idle?.cancel();
    _idle = Timer(adapter.linger, () {
      if (!_watched) _close();
    });
  }

  void _close() {
    _retry?.cancel();
    _changes?.cancel();
    _changes = null;
    final client = _client;
    _client = null;
    _states.clear();
    client?.close().ignore();
  }

  void dispose() {
    _disposed = true;
    _idle?.cancel();
    _close();
    for (final list in _listeners.values) {
      for (final out in list) {
        if (!out.isClosed) out.add(const DeviceState.unreachable());
      }
    }
  }
}
