import 'dart:async';

import '../../model/device.dart';
import '../device_adapter.dart';
import 'hue_bridge.dart';
import 'hue_lights.dart';
import 'hue_link.dart';

/// Where a Hue light is: its home's bridge and its `light` resource id.
/// Saved as `HomeDevice.address`.
class HueAddress {
  const HueAddress(this.lightId);
  final String lightId;

  static HueAddress? parse(Map<String, dynamic> json) {
    final light = json['light'];
    return light is String && light.isNotEmpty ? HueAddress(light) : null;
  }

  Map<String, dynamic> toJson() => {'light': lightId};
}

/// Lights and smart plugs on a Philips Hue Bridge, through the bridge's own
/// local API (CLIP v2) on the home network: no Hue account, no cloud. One
/// bridge per home. Its key stays in the home's encrypted vault item, and
/// the app only talks to the bridge whose certificate it saw when pairing.
class HueAdapter implements DeviceAdapter {
  HueAdapter({
    required this.loadBridge,
    HueConnect? connect,
    this.linger = const Duration(seconds: 30),
    this.retryAfter = const [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(seconds: 60),
    ],
  }) : connect = connect ?? connectHueHttp;

  static const adapterId = 'hue';

  /// The home's bridge, or null when it has none.
  final Future<HueBridge?> Function(String homeId) loadBridge;
  final HueConnect connect;

  /// How long the bridge is listened to after the last light left the
  /// screen.
  final Duration linger;

  /// Pauses between attempts to reconnect, the last one repeated.
  final List<Duration> retryAfter;

  final _sessions = <String, _HueSession>{};
  var _disposed = false;

  @override
  String get id => adapterId;

  /// Asks the bridge at [host] for a key. Its round button must have been
  /// pressed in the last 30 seconds, or this throws
  /// [HueFailure.pressButton].
  Future<HueBridge> pair({required String homeId, required String host}) async {
    final link = connect(host);
    try {
      final json = await link.request('POST', '/api', {
        'devicetype': 'zt_home#phone',
      });
      final first = json is List && json.isNotEmpty ? json.first : null;
      if (first is! Map) throw const HueException(HueFailure.notHue);
      final success = first['success'];
      final key = success is Map ? success['username'] : null;
      if (key is String && key.isNotEmpty) {
        return HueBridge(
          homeId: homeId,
          host: host,
          key: key,
          certificate: link.seenCertificate,
        );
      }
      final error = first['error'];
      if (error is! Map) throw const HueException(HueFailure.notHue);
      if (error['type'] == 101) {
        throw const HueException(HueFailure.pressButton);
      }
      throw HueException(HueFailure.failed, '${error['description'] ?? ''}');
    } finally {
      link.close();
    }
  }

  /// The lights and plugs [bridge] has. Throws [HueException].
  Future<List<HueLight>> lights(HueBridge bridge) async {
    final link = connect(bridge.host, key: bridge.key, pin: bridge.certificate);
    try {
      return [
        for (final r in await _resources(link, 'light')) ?HueLight.from(r),
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } finally {
      link.close();
    }
  }

  static Future<List<Map<String, dynamic>>> _resources(
    HueLink link,
    String type,
  ) async {
    final json = await link.request('GET', '/clip/v2/resource/$type');
    final data = json is Map ? json['data'] : null;
    if (data is! List) throw const HueException(HueFailure.notHue);
    return [
      for (final item in data)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  /// The device to save for [light].
  HomeDevice deviceFor({
    required String id,
    required String homeId,
    required HueLight light,
    String? roomId,
  }) => HomeDevice(
    id: id,
    homeId: homeId,
    roomId: roomId,
    name: light.name,
    type: light.type,
    adapter: adapterId,
    address: HueAddress(light.id).toJson(),
    capabilities: light.capabilities,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );

  Future<_HueSession?> _session(String homeId) async {
    final bridge = await loadBridge(homeId);
    if (bridge == null || _disposed) return null;
    final old = _sessions[homeId];
    if (old != null && old.bridge.signature == bridge.signature) return old;
    final next = _sessions[homeId] = _HueSession(this, bridge);
    if (old != null) {
      // Paired again or moved: what is on screen follows the new bridge.
      next._listeners.addAll(old._listeners);
      old._listeners.clear();
      old.dispose();
      if (next._watched) next._start();
    }
    return next;
  }

  @override
  Stream<DeviceState> watch(HomeDevice device) {
    final address = HueAddress.parse(device.address);
    if (address == null) return Stream.value(const DeviceState.unreachable());
    late final StreamController<DeviceState> out;
    _HueSession? session;
    out = StreamController<DeviceState>(
      onListen: () async {
        session = await _session(device.homeId);
        if (out.isClosed) return;
        if (session == null) {
          out.add(const DeviceState.unreachable());
          return;
        }
        session!.listen(address.lightId, out);
      },
      onCancel: () {
        // The session may have been replaced since (paired again).
        _sessions[device.homeId]?.leave(address.lightId, out);
        session?.leave(address.lightId, out);
        return out.close();
      },
    );
    return out.stream;
  }

  @override
  Future<void> send(HomeDevice device, DeviceCommand command) async {
    final address = HueAddress.parse(device.address);
    if (address == null) {
      throw StateError('${device.name} isn\'t a Hue light');
    }
    final session = await _session(device.homeId);
    if (session == null) {
      throw const HueException(HueFailure.unreachable, 'No Hue Bridge');
    }
    await session.send(address.lightId, command);
  }

  @override
  Future<void> forget(
    HomeDevice device, {
    required List<HomeDevice> others,
  }) async {
    // Nothing to tell the bridge: the light stays on it. The connection
    // closes once nothing of the home is left to watch.
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

/// One home's bridge: the latest state of each light, and who is watching
/// which.
class _HueSession {
  _HueSession(this.adapter, this.bridge)
    : link = adapter.connect(
        bridge.host,
        key: bridge.key,
        pin: bridge.certificate,
      );
  final HueAdapter adapter;
  final HueBridge bridge;
  final HueLink link;

  final _listeners = <String, List<StreamController<DeviceState>>>{};
  final _lights = <String, Map<String, dynamic>>{};

  /// By device id: whether the bridge reaches it over Zigbee.
  final _connected = <String, bool>{};
  StreamSubscription<Map<String, dynamic>>? _events;
  Future<void>? _starting;
  Timer? _retry;
  Timer? _idle;
  var _loaded = false;
  var _failures = 0;
  var _disposed = false;

  bool get _watched => _listeners.values.any((l) => l.isNotEmpty);

  DeviceState _read(String light) {
    if (!_loaded) return const DeviceState.unreachable();
    final resource = _lights[light];
    return hueRead(resource, connected: _connected[hueOwner(resource)] ?? true);
  }

  void listen(String light, StreamController<DeviceState> out) {
    _idle?.cancel();
    (_listeners[light] ??= []).add(out);
    if (_loaded) {
      out.add(_read(light));
    } else {
      _start();
    }
  }

  void leave(String light, StreamController<DeviceState> out) {
    _listeners[light]?.remove(out);
    if (!_watched) leaveAll();
  }

  void _emit(String light) {
    final state = _read(light);
    for (final out in [...?_listeners[light]]) {
      if (!out.isClosed) out.add(state);
    }
  }

  void _emitAll() {
    for (final light in _listeners.keys) {
      _emit(light);
    }
  }

  void _start() {
    if (_starting != null || _loaded || _disposed) return;
    _retry?.cancel();
    _starting = _load().whenComplete(() => _starting = null);
  }

  Future<void> _load() async {
    try {
      final lights = await HueAdapter._resources(link, 'light');
      final reach = await HueAdapter._resources(link, 'zigbee_connectivity');
      if (_disposed) return;
      _lights
        ..clear()
        ..addAll({
          for (final l in lights)
            if (l['id'] is String) l['id'] as String: l,
        });
      _connected
        ..clear()
        ..addAll({
          for (final r in reach) ?hueOwner(r): r['status'] == 'connected',
        });
      _events = link.events().listen(
        _changed,
        onError: (Object _) => _dropped(),
        onDone: _dropped,
        cancelOnError: true,
      );
      _loaded = true;
      _failures = 0;
      _emitAll();
    } on Object {
      if (_disposed) return;
      _failures++;
      _emitAll(); // As unreachable: there is no state now.
      _scheduleRetry();
    }
  }

  void _changed(Map<String, dynamic> change) {
    final id = change['id'];
    if (id is! String) return;
    switch (change['type']) {
      case 'light':
        _lights[id] = hueMerge(_lights[id], change);
        _emit(id);
      case 'zigbee_connectivity':
        final owner = hueOwner(change);
        final status = change['status'];
        if (owner == null || status is! String) return;
        _connected[owner] = status == 'connected';
        for (final MapEntry(:key, :value) in _lights.entries) {
          if (hueOwner(value) == owner) _emit(key);
        }
    }
  }

  void _dropped() {
    if (!_loaded) return;
    _events?.cancel();
    _events = null;
    _loaded = false;
    if (_disposed) return;
    _failures++;
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

  Future<void> send(String light, DeviceCommand command) async {
    final body = hueWrite(command);
    if (body == null) {
      throw StateError('A Hue light can\'t do ${command.capability.name}');
    }
    try {
      final answer = await link.request(
        'PUT',
        '/clip/v2/resource/light/$light',
        body,
      );
      final refused = hueErrorText(answer);
      if (refused != null) throw HueException(HueFailure.failed, refused);
    } finally {
      if (!_watched) leaveAll();
    }
  }

  void leaveAll() {
    _idle?.cancel();
    _idle = Timer(adapter.linger, () {
      if (!_watched) _stop();
    });
  }

  void _stop() {
    _retry?.cancel();
    _events?.cancel();
    _events = null;
    _loaded = false;
    _lights.clear();
    _connected.clear();
  }

  void dispose() {
    _disposed = true;
    _idle?.cancel();
    _stop();
    link.close();
    for (final list in _listeners.values) {
      for (final out in list) {
        if (!out.isClosed) out.add(const DeviceState.unreachable());
      }
    }
  }
}
