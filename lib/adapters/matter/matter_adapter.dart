import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../../model/device.dart';
import '../device_adapter.dart';
import 'der.dart';
import 'matter_bridge.dart';
import 'matter_fabric.dart';
import 'matter_setup_code.dart';
import 'matter_tlv.dart';

/// The parts of Matter this version reads and controls.
abstract final class MatterIds {
  // Clusters (features of a device).
  static const onOff = 0x0006;
  static const levelControl = 0x0008;
  static const descriptor = 0x001D;
  static const basicInformation = 0x0028;

  // Device types that are lights (on/off, dimmable, colour temperature,
  // extended colour) and plugs (on/off, dimmable).
  static const lights = {0x0100, 0x0101, 0x010C, 0x010D};
  static const plugs = {0x010A, 0x010B};
  static const switches = {0x0103, 0x0104, 0x0105, 0x000F};
}

/// Where a Matter device is: its node in the home's fabric, and which part
/// (endpoint) of that node it is. A power strip is one node with a device
/// per socket.
@immutable
class MatterAddress {
  const MatterAddress({required this.nodeId, required this.endpoint});
  final String nodeId;
  final int endpoint;

  Map<String, dynamic> toJson() => {'nodeId': nodeId, 'endpoint': endpoint};

  static MatterAddress? parse(Map<String, dynamic> json) {
    final nodeId = json['nodeId'];
    final endpoint = json['endpoint'];
    if (nodeId is! String || nodeId.length != 16 || endpoint is! num) {
      return null;
    }
    return MatterAddress(nodeId: nodeId, endpoint: endpoint.toInt());
  }
}

/// What a device said it is, once it has joined: one entry per part that
/// can be shown.
@immutable
class MatterPart {
  const MatterPart({
    required this.endpoint,
    required this.type,
    required this.capabilities,
  });
  final int endpoint;
  final DeviceType type;
  final Set<Capability> capabilities;
}

/// Reads a device's own description (its Descriptor clusters) into the
/// parts the app shows. A device with nothing this version controls still
/// gives one part, so it is listed and can be removed.
List<MatterPart> matterParts(List<MatterAttribute> attributes) {
  final types = <int, Set<int>>{};
  final clusters = <int, Set<int>>{};
  for (final a in attributes) {
    if (a.cluster != MatterIds.descriptor || a.value is! List) continue;
    final list = a.value as List;
    if (a.attribute == 0) {
      // DeviceTypeList: structures of {0: device type, 1: revision}.
      types[a.endpoint] = {
        for (final item in list)
          if (item is Map && item[0] is int) item[0] as int,
      };
    } else if (a.attribute == 1) {
      // ServerList: the clusters the endpoint has.
      clusters[a.endpoint] = {
        for (final item in list) ?(item is int ? item : null),
      };
    }
  }
  final parts = <MatterPart>[];
  for (final endpoint in clusters.keys.toList()..sort()) {
    // Endpoint 0 is the device itself (its name, its network), not a part.
    if (endpoint == 0) continue;
    final has = clusters[endpoint]!;
    if (!has.contains(MatterIds.onOff)) continue;
    final kinds = types[endpoint] ?? const <int>{};
    parts.add(
      MatterPart(
        endpoint: endpoint,
        type: kinds.any(MatterIds.lights.contains)
            ? DeviceType.light
            : kinds.any(MatterIds.plugs.contains)
            ? DeviceType.plug
            : kinds.any(MatterIds.switches.contains)
            ? DeviceType.wallSwitch
            : has.contains(MatterIds.levelControl)
            ? DeviceType.light
            : DeviceType.plug,
        capabilities: {
          Capability.onOff,
          if (has.contains(MatterIds.levelControl)) Capability.brightness,
        },
      ),
    );
  }
  if (parts.isEmpty) {
    final first =
        (clusters.keys.where((e) => e != 0).toList()..sort()).firstOrNull;
    parts.add(
      MatterPart(
        endpoint: first ?? 1,
        type: DeviceType.other,
        capabilities: const {},
      ),
    );
  }
  return parts;
}

/// Matter devices, in the home's own fabric (see [MatterFabric]).
///
/// The Matter library controls one fabric at a time, so the adapter serves
/// the home that was asked for last: the home on screen.
class MatterAdapter implements DeviceAdapter {
  MatterAdapter({
    required this.bridge,
    required this.loadFabric,
    required this.makeFabric,
    required this.preferences,
    this.linger = const Duration(seconds: 20),
    this.retryAfter = const [5, 10, 20, 40, 60],
  });

  static const adapterId = 'matter';

  final MatterBridge bridge;

  /// The home's saved fabric, or null when it has none.
  final Future<MatterFabric?> Function(String homeId) loadFabric;

  /// The home's fabric, made if there is none yet (adding a first device).
  final Future<MatterFabric> Function(String homeId) makeFabric;

  /// Where this phone keeps which node it is in each fabric.
  final PreferencesStore preferences;

  /// How long a subscription stays open after its last listener left.
  final Duration linger;

  /// Seconds between attempts to reach a device that doesn't answer.
  final List<int> retryAfter;

  final _sessions = <String, _NodeSession>{};
  Future<void> _lock = Future.value();
  String? _activeFabric;
  String? _pairing;
  var _adding = false;
  var _abandoned = false;
  var _disposed = false;

  @override
  String get id => adapterId;

  /// Runs [action] after the ones before it: the library does one thing
  /// about fabrics at a time.
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _lock.then((_) => action());
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Makes the library control [fabric], as this phone's node in it.
  Future<void> _use(MatterFabric fabric) async {
    if (_activeFabric == fabric.fabricId) return;
    // The devices of the home that was served until now go quiet.
    for (final session in _sessions.values.toList()) {
      if (session.fabricId != fabric.fabricId) session.suspend();
    }
    _activeFabric = null;
    final key = await bridge.phoneKey(fabric.fabricId);
    final node = await _phoneNode(fabric, key);
    await bridge.start(
      fabricId: fabric.fabricId,
      rootCert: fabric.rootCert,
      certificate: node.cert,
      ipk: fabric.ipk,
      adminSubject: fabric.adminSubject,
      issue: (csr) async {
        final nodeId = _pairing;
        if (nodeId == null) throw StateError('No device is being added');
        return fabric.issueDevice(csr, nodeId: nodeId).cert;
      },
    );
    _activeFabric = fabric.fabricId;
  }

  /// This phone's certificate in [fabric]: the saved one while its key is
  /// the same, else a new one for the node the phone already was.
  Future<MatterNode> _phoneNode(MatterFabric fabric, Uint8List key) async {
    final name = 'matter.node.${fabric.fabricId}';
    String? nodeId;
    try {
      final saved = jsonDecode(await preferences.read(name) ?? '') as Map;
      nodeId = saved['nodeId'] as String?;
      if (saved['key'] == bytesHex(key) && nodeId != null) {
        return MatterNode(
          nodeId: nodeId,
          cert: base64Decode(saved['cert'] as String),
        );
      }
    } on Object {
      // Nothing saved, or not readable: a new certificate.
    }
    MatterNode node;
    try {
      node = fabric.issueController(key, nodeId: nodeId);
    } on MatterCertException {
      node = fabric.issueController(key);
    }
    await preferences.write(
      name,
      jsonEncode({
        'nodeId': node.nodeId,
        'key': bytesHex(key),
        'cert': base64Encode(node.cert),
      }),
    );
    return node;
  }

  /// Adds the device [code] belongs to (its QR code's text or the typed
  /// code) to the home, and returns its parts as devices ready to save.
  /// The device must be in pairing mode and on the home network. Throws
  /// [MatterException], and what [makeFabric] throws.
  Future<List<HomeDevice>> pair({
    required String homeId,
    required String? roomId,
    required String name,
    required String code,
    required String Function() newId,
    MatterWifi? wifi,
  }) => _serial(() async {
    _adding = true;
    _abandoned = false;
    try {
      return await _pair(homeId, roomId, name, code, newId, wifi);
    } finally {
      _adding = false;
    }
  });

  Future<List<HomeDevice>> _pair(
    String homeId,
    String? roomId,
    String name,
    String code,
    String Function() newId,
    MatterWifi? wifi,
  ) async {
    void checkAbandoned() {
      if (_abandoned) {
        throw const MatterException(MatterFailure.failed, 'Cancelled');
      }
    }

    final fabric = await makeFabric(homeId);
    checkAbandoned();
    await _use(fabric);
    checkAbandoned();
    final nodeId = matterNewNodeId();
    _pairing = nodeId;
    try {
      await bridge.pair(
        nodeId: nodeId,
        code: MatterSetupCode.normalize(code),
        wifi: wifi,
      );
    } finally {
      _pairing = null;
    }
    final List<MatterPart> parts;
    try {
      parts = matterParts(await _describe(nodeId));
    } on Object {
      // It joined but can't be read: don't leave it in the fabric with
      // nothing in the app to remove it by.
      try {
        await bridge.remove(nodeId);
      } on Object {
        // It will be forgotten when it is reset.
      }
      rethrow;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    return [
      for (final (i, part) in parts.indexed)
        HomeDevice(
          id: newId(),
          homeId: homeId,
          roomId: roomId,
          name: parts.length == 1 ? name : '$name ${i + 1}',
          type: part.type,
          adapter: adapterId,
          address: MatterAddress(
            nodeId: nodeId,
            endpoint: part.endpoint,
          ).toJson(),
          capabilities: part.capabilities,
          createdAt: now + i,
        ),
    ];
  }

  /// A device that just joined can take a moment to answer.
  Future<List<MatterAttribute>> _describe(String nodeId) async {
    const paths = [
      MatterPath(null, MatterIds.descriptor, 0),
      MatterPath(null, MatterIds.descriptor, 1),
    ];
    try {
      return await bridge.read(nodeId, paths);
    } on MatterException {
      await Future<void>.delayed(const Duration(seconds: 2));
      return bridge.read(nodeId, paths);
    }
  }

  /// Gives up adding a device (the user went back). A device that has
  /// already joined by then is still returned by [pair], to be saved.
  Future<void> cancelPair() async {
    if (!_adding) return;
    _abandoned = true;
    if (_pairing == null) return;
    try {
      await bridge.cancelPair();
    } on Object {
      // Nothing was running.
    }
  }

  /// Makes the library serve the device's home. False when the home has
  /// no fabric (its key is gone) or the library isn't available.
  Future<String?> _fabricOf(HomeDevice device) => _serial(() async {
    final fabric = await loadFabric(device.homeId);
    if (fabric == null || !fabric.isUsable) return null;
    await _use(fabric);
    return fabric.fabricId;
  });

  @override
  Stream<DeviceState> watch(HomeDevice device) {
    final address = MatterAddress.parse(device.address);
    if (address == null || _disposed) {
      return Stream.value(const DeviceState.unreachable());
    }
    final session = _sessions.putIfAbsent(
      '${device.homeId}/${address.nodeId}',
      () => _NodeSession(this, device, address.nodeId),
    );
    return session.watch(address.endpoint);
  }

  @override
  Future<void> send(HomeDevice device, DeviceCommand command) async {
    final address = MatterAddress.parse(device.address);
    if (address == null || !device.can(command.capability)) {
      throw StateError('${device.name} can\'t do ${command.capability.name}');
    }
    final (int cluster, int id, Uint8List fields) = switch (command) {
      DeviceCommand(capability: Capability.onOff, value: final bool on) => (
        MatterIds.onOff,
        // Off is command 0, On is command 1.
        on ? 1 : 0,
        matterTlvStruct(),
      ),
      DeviceCommand(capability: Capability.brightness, value: final num v) => (
        MatterIds.levelControl,
        // MoveToLevelWithOnOff: level 1 to 254, at once, no options.
        4,
        matterTlvStruct([
          MatterTlvUint(0, (v * 254 / 100).round().clamp(1, 254)),
          const MatterTlvUint(1, 0),
          const MatterTlvUint(2, 0),
          const MatterTlvUint(3, 0),
        ]),
      ),
      _ => throw StateError(
        '${device.name} can\'t do ${command.capability.name}',
      ),
    };
    if (await _fabricOf(device) == null) {
      throw const MatterException(MatterFailure.unreachable, 'No fabric');
    }
    await bridge.invoke(
      address.nodeId,
      endpoint: address.endpoint,
      cluster: cluster,
      command: id,
      fields: fields,
    );
  }

  /// The last part of a node that is deleted tells the device to leave
  /// the fabric, so it can be added again, here or elsewhere. A device
  /// that is unplugged can't be told; it needs a reset to pair again.
  @override
  Future<void> forget(
    HomeDevice device, {
    required List<HomeDevice> others,
  }) async {
    final address = MatterAddress.parse(device.address);
    if (address == null) return;
    final shared = others.any(
      (d) =>
          d.homeId == device.homeId &&
          MatterAddress.parse(d.address)?.nodeId == address.nodeId,
    );
    if (shared) return;
    _sessions.remove('${device.homeId}/${address.nodeId}')?.dispose();
    try {
      if (await _fabricOf(device) == null) return;
      await bridge.remove(address.nodeId);
    } on Object {
      // Unplugged or already reset.
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    for (final s in _sessions.values.toList()) {
      s.dispose();
    }
    _sessions.clear();
  }
}

/// One subscription to a node, shared by the devices that are its parts.
class _NodeSession {
  _NodeSession(this.adapter, this.device, this.nodeId);
  final MatterAdapter adapter;
  final HomeDevice device;
  final String nodeId;

  String? fabricId;
  final _listeners = <int, List<StreamController<DeviceState>>>{};
  final _values = <(int, int, int), Object?>{};
  StreamSubscription<MatterEvent>? _subscription;
  Timer? _retry;
  Timer? _lingering;
  var _attempt = 0;
  var _running = false;
  var _connecting = false;
  var _reachable = false;
  var _disposed = false;

  bool get _watched => _listeners.values.any((l) => l.isNotEmpty);

  Stream<DeviceState> watch(int endpoint) {
    late final StreamController<DeviceState> controller;
    controller = StreamController<DeviceState>(
      onListen: () {
        _lingering?.cancel();
        _listeners.putIfAbsent(endpoint, () => []).add(controller);
        controller.add(_state(endpoint));
        if (!_running) _start();
      },
      onCancel: () {
        _listeners[endpoint]?.remove(controller);
        if (!_watched) {
          _lingering?.cancel();
          _lingering = Timer(adapter.linger, () {
            if (!_watched) _stop();
          });
        }
      },
    );
    return controller.stream;
  }

  DeviceState _state(int endpoint) {
    if (!_reachable) return const DeviceState.unreachable();
    final on = _values[(endpoint, MatterIds.onOff, 0)];
    final level = _values[(endpoint, MatterIds.levelControl, 0)];
    return DeviceState(
      values: {
        if (on is bool) Capability.onOff: on,
        if (level is int)
          Capability.brightness: (level * 100 / 254).round().clamp(1, 100),
      },
    );
  }

  void _emit() {
    for (final MapEntry(key: endpoint, value: listeners)
        in _listeners.entries) {
      final state = _state(endpoint);
      for (final l in listeners.toList()) {
        if (!l.isClosed) l.add(state);
      }
    }
  }

  void _start() {
    _running = true;
    _attempt = 0;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (!_running || _disposed || _connecting || _subscription != null) return;
    _connecting = true;
    try {
      fabricId = await adapter._fabricOf(device);
      if (!_running || _disposed) return;
      if (fabricId == null) {
        _down();
        return;
      }
      _subscription = adapter.bridge
          .subscribe(nodeId, const [
            MatterPath(null, MatterIds.onOff, 0),
            MatterPath(null, MatterIds.levelControl, 0),
          ])
          .listen(
            _onEvent,
            onError: (Object _) => _lost(),
            onDone: _lost,
            cancelOnError: true,
          );
    } on Object {
      _down();
    } finally {
      _connecting = false;
    }
  }

  void _onEvent(MatterEvent event) {
    switch (event) {
      case MatterReport(:final attributes):
        for (final a in attributes) {
          _values[(a.endpoint, a.cluster, a.attribute)] = a.value;
        }
        _reachable = true;
        _attempt = 0;
      case MatterReachable(:final reachable):
        _reachable = reachable;
    }
    _emit();
  }

  /// The subscription ended by itself.
  void _lost() {
    _subscription = null;
    _down();
  }

  void _down() {
    _reachable = false;
    _emit();
    if (!_running || _disposed) return;
    final seconds =
        adapter.retryAfter[_attempt.clamp(0, adapter.retryAfter.length - 1)];
    _attempt++;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: seconds), _connect);
  }

  /// The library now serves another home.
  void suspend() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    _reachable = false;
    _emit();
    _retry?.cancel();
    // Only a device someone is looking at asks for its home back.
    if (_running && _watched && !_disposed) {
      _retry = Timer(Duration(seconds: adapter.retryAfter.first), _connect);
    } else {
      _running = false;
    }
  }

  void _stop() {
    _running = false;
    _retry?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    _reachable = false;
  }

  void dispose() {
    _disposed = true;
    _lingering?.cancel();
    _stop();
    for (final listeners in _listeners.values) {
      for (final l in listeners.toList()) {
        unawaited(l.close());
      }
    }
    _listeners.clear();
  }
}
