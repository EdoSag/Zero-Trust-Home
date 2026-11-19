import 'dart:async';
import 'dart:typed_data';

import '../../model/device.dart';
import '../device_adapter.dart';
import 'tuya_codec.dart';
import 'tuya_discovery.dart';
import 'tuya_link.dart';

/// Where a Tuya device is and how its data points map to what the app
/// shows. Saved as `HomeDevice.address`, encrypted with the device item.
class TuyaAddress {
  const TuyaAddress({
    required this.deviceId,
    required this.localKey,
    required this.ip,
    required this.version,
    this.onOffDp,
    this.powerDp,
    this.brightnessDp,
  });

  final String deviceId;

  /// 16 characters. Stays inside the encrypted item.
  final String localKey;
  final String ip;
  final TuyaVersion version;

  /// The data point (its number, as text) behind each capability, when
  /// the device has it.
  final String? onOffDp;
  final String? powerDp;
  final String? brightnessDp;

  static TuyaAddress? parse(Map<String, dynamic> json) {
    final id = json['deviceId'];
    final key = json['localKey'];
    final ip = json['ip'];
    final version = TuyaVersion.parse(json['version']);
    if (id is! String || key is! String || ip is! String || version == null) {
      return null;
    }
    final dps = json['dps'] is Map ? json['dps'] as Map : const {};
    return TuyaAddress(
      deviceId: id,
      localKey: key,
      ip: ip,
      version: version,
      onOffDp: dps['onOff'] as String?,
      powerDp: dps['power'] as String?,
      brightnessDp: dps['brightness'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'localKey': localKey,
    'ip': ip,
    'version': version.text,
    'dps': {'onOff': ?onOffDp, 'power': ?powerDp, 'brightness': ?brightnessDp},
  };

  TuyaAddress withIp(String ip) => TuyaAddress(
    deviceId: deviceId,
    localKey: localKey,
    ip: ip,
    version: version,
    onOffDp: onOffDp,
    powerDp: powerDp,
    brightnessDp: brightnessDp,
  );

  /// Everything a connection depends on.
  String get _signature => '$deviceId|$localKey|$ip|${version.text}';

  Set<Capability> get capabilities => {
    if (onOffDp != null) Capability.onOff,
    if (powerDp != null) Capability.power,
    if (brightnessDp != null) Capability.brightness,
  };

  /// The app's values for the data points a device reported.
  Map<Capability, Object> read(Map<String, dynamic> dps) {
    final values = <Capability, Object>{};
    final on = dps[onOffDp];
    if (on is bool) values[Capability.onOff] = on;
    // Tuya reports power in tenths of a watt.
    final power = dps[powerDp];
    if (power is num) values[Capability.power] = power / 10;
    // Brightness runs from 10 to 1000.
    final level = dps[brightnessDp];
    if (level is num) {
      values[Capability.brightness] = ((level - 10) / 990 * 100)
          .clamp(0, 100)
          .round();
    }
    return values;
  }

  /// The data points to set for [command]. Null when this device can't.
  Map<String, dynamic>? write(DeviceCommand command) {
    switch (command.capability) {
      case Capability.onOff when onOffDp != null && command.value is bool:
        return {onOffDp!: command.value};
      case Capability.brightness
          when brightnessDp != null && command.value is num:
        final percent = (command.value as num).clamp(0, 100);
        return {brightnessDp!: (10 + percent * 9.9).round()};
      default:
        return null;
    }
  }
}

/// What kind of device its data points make it, read once when it is
/// added. Tuya devices don't say what they are locally, but the numbering
/// is the same across brands:
/// - plugs and switches: 1 = on/off, 19 = power (older ones: 5)
/// - lights: 20 = on/off, 22 = brightness
({DeviceType type, String? onOff, String? power, String? brightness})
tuyaProfile(Map<String, dynamic> dps) {
  if (dps['20'] is bool && dps['1'] is! bool) {
    return (
      type: DeviceType.light,
      onOff: '20',
      power: null,
      brightness: dps['22'] is num ? '22' : null,
    );
  }
  if (dps['1'] is bool) {
    final String? power;
    if (dps['19'] is num) {
      power = '19';
    } else if (dps['5'] is num && dps['4'] is num && dps['6'] is num) {
      power = '5';
    } else {
      power = null;
    }
    return (type: DeviceType.plug, onOff: '1', power: power, brightness: null);
  }
  return (type: DeviceType.other, onOff: null, power: null, brightness: null);
}

/// Opens a link to a device. Tests pass their own.
typedef TuyaLinkOpener =
    Future<TuyaLink> Function({
      required String host,
      required String deviceId,
      required Uint8List localKey,
      required TuyaVersion version,
    });

Future<TuyaLink> _openLink({
  required String host,
  required String deviceId,
  required Uint8List localKey,
  required TuyaVersion version,
}) => TuyaLink.open(
  host: host,
  deviceId: deviceId,
  localKey: localKey,
  version: version,
);

/// Tuya / Smart Life devices, straight over the home network: no Tuya
/// cloud once the device's local key is known. Works for plugs, switches
/// and lights on protocol 3.3, 3.4 and 3.5.
class TuyaAdapter implements DeviceAdapter {
  TuyaAdapter({
    TuyaDiscovery? discovery,
    TuyaLinkOpener? open,
    this.onMoved,
    this.pollEvery = const Duration(seconds: 10),
    this.linger = const Duration(seconds: 3),
  }) : discovery = discovery ?? TuyaDiscovery(),
       _open = open ?? _openLink;

  static const adapterId = 'tuya';

  final TuyaDiscovery discovery;
  final TuyaLinkOpener _open;

  /// Called when a device answers at a new address (the router gave it
  /// another one), so the new address can be saved.
  final void Function(HomeDevice device, String ip)? onMoved;

  /// How often an open connection is kept alive and power is re-read.
  final Duration pollEvery;

  /// How long a connection stays open after its last listener left.
  final Duration linger;

  final _sessions = <String, _Session>{};

  @override
  String get id => adapterId;

  /// Connects with what the user entered, reads the device's data points
  /// and returns the device ready to save. Throws [TuyaException].
  Future<HomeDevice> pair({
    required String id,
    required String homeId,
    required String? roomId,
    required String name,
    required String deviceId,
    required String ip,
    required TuyaVersion version,
    required String localKey,
  }) async {
    final key = tuyaParseLocalKey(localKey);
    if (key == null) {
      throw const TuyaException(TuyaFailure.keyRejected, 'Not 16 characters');
    }
    final link = await _open(
      host: ip,
      deviceId: deviceId,
      localKey: key,
      version: version,
    );
    try {
      final dps = await link.query();
      final profile = tuyaProfile(dps);
      final address = TuyaAddress(
        deviceId: deviceId,
        localKey: localKey.trim(),
        ip: ip,
        version: version,
        onOffDp: profile.onOff,
        powerDp: profile.power,
        brightnessDp: profile.brightness,
      );
      return HomeDevice(
        id: id,
        homeId: homeId,
        roomId: roomId,
        name: name,
        type: profile.type,
        adapter: adapterId,
        address: address.toJson(),
        capabilities: address.capabilities,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
    } finally {
      await link.close();
    }
  }

  @override
  Stream<DeviceState> watch(HomeDevice device) {
    final address = TuyaAddress.parse(device.address);
    if (address == null) return Stream.value(const DeviceState.unreachable());
    return _session(device, address).watch();
  }

  _Session _session(HomeDevice device, TuyaAddress address) {
    final old = _sessions[device.id];
    if (old != null && old.address._signature == address._signature) {
      old.device = device;
      return old;
    }
    old?.dispose();
    return _sessions[device.id] = _Session(this, device, address);
  }

  @override
  Future<void> forget(
    HomeDevice device, {
    required List<HomeDevice> others,
  }) async {
    final address = TuyaAddress.parse(device.address);
    if (address != null) discovery.forget(address.deviceId);
  }

  @override
  Future<void> send(HomeDevice device, DeviceCommand command) async {
    final address = TuyaAddress.parse(device.address);
    final dps = address?.write(command);
    if (address == null || dps == null) {
      throw StateError('${device.name} can\'t do ${command.capability.name}');
    }
    final session = _sessions[device.id];
    final link = session?.link;
    if (link != null && link.isOpen) {
      await link.set(dps);
      return;
    }
    // Not on screen (a widget, an automation): one short connection.
    final key = tuyaParseLocalKey(address.localKey);
    if (key == null) throw const TuyaException(TuyaFailure.keyRejected);
    Future<TuyaLink> open(String host) => _open(
      host: host,
      deviceId: address.deviceId,
      localKey: key,
      version: address.version,
    );
    final heard = discovery.found[address.deviceId]?.ip;
    TuyaLink once;
    try {
      once = await open(heard ?? address.ip);
    } on TuyaException catch (e) {
      // What was heard earlier can be stale while the saved address is
      // newer (another phone followed the device): try that one too.
      if (heard == null ||
          heard == address.ip ||
          e.failure != TuyaFailure.unreachable) {
        rethrow;
      }
      discovery.forget(address.deviceId);
      once = await open(address.ip);
    }
    try {
      await once.set(dps);
    } finally {
      await once.close();
    }
  }

  Future<void> dispose() async {
    for (final s in _sessions.values.toList()) {
      s.dispose();
    }
    _sessions.clear();
    await discovery.dispose();
  }
}

/// Keeps one device connected while anyone watches it: reconnects with
/// growing pauses, follows the device to a new address, keeps the
/// connection alive and re-reads power.
class _Session {
  _Session(this.adapter, this.device, this.address);

  final TuyaAdapter adapter;
  HomeDevice device;
  TuyaAddress address;

  final _listeners = <StreamController<DeviceState>>{};
  DeviceState _state = const DeviceState.unreachable();
  var _dps = <String, dynamic>{};
  TuyaLink? link;
  StreamSubscription<Map<String, dynamic>>? _changes;
  StreamSubscription<Map<String, TuyaAnnouncement>>? _finding;
  Timer? _poll;
  Timer? _retry;
  Timer? _lingering;
  var _running = false;
  var _disposed = false;
  var _attempt = 0;
  var _connecting = false;

  Stream<DeviceState> watch() {
    late final StreamController<DeviceState> controller;
    controller = StreamController<DeviceState>(
      onListen: () {
        _lingering?.cancel();
        _listeners.add(controller);
        controller.add(_state);
        if (!_running) _start();
      },
      onCancel: () {
        _listeners.remove(controller);
        if (_listeners.isEmpty) {
          _lingering?.cancel();
          _lingering = Timer(adapter.linger, () {
            if (_listeners.isEmpty) _stop();
          });
        }
      },
    );
    return controller.stream;
  }

  void _emit(DeviceState state) {
    _state = state;
    for (final l in _listeners.toList()) {
      if (!l.isClosed) l.add(state);
    }
  }

  void _start() {
    _running = true;
    _attempt = 0;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (!_running || _disposed || _connecting) return;
    final key = tuyaParseLocalKey(address.localKey);
    if (key == null) return;
    _connecting = true;
    // The address the device announced last wins over the saved one, until
    // nothing answers there.
    final host = adapter.discovery.found[address.deviceId]?.ip ?? address.ip;
    TuyaLink? opened;
    try {
      opened = await adapter._open(
        host: host,
        deviceId: address.deviceId,
        localKey: key,
        version: address.version,
      );
      if (!_running || _disposed) {
        await opened.close();
        return;
      }
      link = opened;
      _changes = opened.changes.listen(_onDps);
      final current = opened;
      unawaited(current.done.then((_) => _onClosed(current)));
      _onDps(await opened.query());
      _attempt = 0;
      _stopFinding();
      if (host != address.ip) {
        address = address.withIp(host);
        adapter.onMoved?.call(device, host);
      }
      _poll?.cancel();
      _poll = Timer.periodic(adapter.pollEvery, (_) => _tick(current));
      _refreshPower(current);
    } on Object {
      // Nothing answered where the device was last heard: that can be
      // stale, so the next attempt goes to the saved address.
      if (opened == null && host != address.ip) {
        adapter.discovery.forget(address.deviceId);
      }
      // When the link closed by itself, _onClosed already handled it.
      if (opened == null || link == opened) {
        link = null;
        unawaited(opened?.close());
        _onDown();
      }
    } finally {
      _connecting = false;
    }
  }

  void _onDps(Map<String, dynamic> dps) {
    _dps = {..._dps, ...dps};
    _emit(DeviceState(values: address.read(_dps)));
  }

  void _tick(TuyaLink opened) {
    if (!opened.isOpen) return;
    // A failed heartbeat closes the link, which reconnects.
    opened.heartbeat().then((_) {}, onError: (_) {});
    _refreshPower(opened);
  }

  void _refreshPower(TuyaLink opened) {
    final dp = int.tryParse(address.powerDp ?? '');
    if (dp != null && opened.isOpen) opened.refresh([dp]);
  }

  void _onClosed(TuyaLink closed) {
    if (link != closed) return;
    link = null;
    _onDown();
  }

  void _onDown() {
    _poll?.cancel();
    unawaited(_changes?.cancel());
    _changes = null;
    _dps = {};
    _emit(const DeviceState.unreachable());
    if (!_running || _disposed) return;
    _startFinding();
    final seconds = [2, 4, 8, 15, 30][_attempt.clamp(0, 4)];
    _attempt++;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: seconds), _connect);
  }

  /// While the device is down, listen for it: it may be back at another
  /// address, and then there's no reason to wait for the next retry.
  void _startFinding() {
    _finding ??= adapter.discovery.watch().listen((found) {
      final seen = found[address.deviceId];
      if (seen != null && seen.ip != address.ip && link == null && _running) {
        _retry?.cancel();
        unawaited(_connect());
      }
    });
  }

  void _stopFinding() {
    unawaited(_finding?.cancel());
    _finding = null;
  }

  void _stop() {
    _running = false;
    _retry?.cancel();
    _poll?.cancel();
    _stopFinding();
    unawaited(_changes?.cancel());
    _changes = null;
    final open = link;
    link = null;
    unawaited(open?.close());
    _state = const DeviceState.unreachable();
    _dps = {};
  }

  void dispose() {
    _disposed = true;
    _lingering?.cancel();
    _stop();
    for (final l in _listeners.toList()) {
      unawaited(l.close());
    }
    _listeners.clear();
  }
}
