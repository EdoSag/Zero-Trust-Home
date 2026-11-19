import 'package:flutter/foundation.dart';

/// What a device is, for its icon and where it is listed.
enum DeviceType {
  light,
  plug,
  wallSwitch,
  sensor,
  lock,
  thermostat,
  blind,
  fan,
  camera,
  other;

  /// A type saved by a newer version of the app reads as [other].
  static DeviceType parse(Object? name) => DeviceType.values.firstWhere(
    (t) => t.name == name,
    orElse: () => DeviceType.other,
  );
}

/// One thing a device can do or report. A device has a set of these; the
/// app builds its controls from them, whatever brand the device is.
///
/// Values in a [DeviceState] and a [DeviceCommand]:
/// - [onOff], [locked], [contact] (true = open), [motion]: `bool`
/// - [brightness], [position] (0 closed to 100 open), [fanSpeed], [humidity],
///   [battery]: `num` from 0 to 100
/// - [colorTemperature]: `num` in kelvin
/// - [color]: `int`, 0xRRGGBB
/// - [temperature], [targetTemperature]: `num` in °C
/// - [power]: `num` in watts; [energy]: `num` in kWh
enum Capability {
  onOff,
  brightness,
  colorTemperature,
  color,
  locked,
  position,
  fanSpeed,
  targetTemperature,
  temperature,
  humidity,
  contact,
  motion,
  power,
  energy,
  battery;

  static Capability? parse(Object? name) {
    for (final c in Capability.values) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// Whether the app can set it, not only read it.
  bool get writable => switch (this) {
    onOff ||
    brightness ||
    colorTemperature ||
    color ||
    locked ||
    position ||
    fanSpeed ||
    targetTemperature => true,
    _ => false,
  };
}

/// A device in a home. How it is reached is the job of its adapter
/// ([adapter] names it, [address] is whatever that adapter needs to find
/// the device again); everything else is the same for every brand.
@immutable
class HomeDevice {
  const HomeDevice({
    required this.id,
    required this.homeId,
    required this.name,
    required this.adapter,
    this.roomId,
    this.type = DeviceType.other,
    this.address = const {},
    this.capabilities = const {},
    this.favourite = false,
    this.createdAt = 0,
  });

  final String id;
  final String homeId;

  /// Null while the device is not placed in a room.
  final String? roomId;
  final String name;
  final DeviceType type;

  /// The id of the `DeviceAdapter` that talks to it: `matter`,
  /// `homeassistant`, `hue`...
  final String adapter;

  /// Adapter-specific: a Matter node id, a Home Assistant entity id, an IP
  /// address and key... Encrypted with the rest of the item.
  final Map<String, dynamic> address;
  final Set<Capability> capabilities;

  /// Shown at the top of the home.
  final bool favourite;
  final int createdAt;

  bool can(Capability c) => capabilities.contains(c);

  static const _unset = Object();

  HomeDevice copyWith({
    Object? roomId = _unset,
    String? name,
    DeviceType? type,
    bool? favourite,
    Map<String, dynamic>? address,
  }) => HomeDevice(
    id: id,
    homeId: homeId,
    roomId: identical(roomId, _unset) ? this.roomId : roomId as String?,
    name: name ?? this.name,
    type: type ?? this.type,
    adapter: adapter,
    address: address ?? this.address,
    capabilities: capabilities,
    favourite: favourite ?? this.favourite,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'homeId': homeId,
    if (roomId != null) 'roomId': roomId,
    'name': name,
    'type': type.name,
    'adapter': adapter,
    'address': address,
    'capabilities': [for (final c in capabilities) c.name],
    'favourite': favourite,
    'createdAt': createdAt,
  };

  static HomeDevice fromJson(String id, Map<String, dynamic> json) =>
      HomeDevice(
        id: id,
        homeId: json['homeId'] as String? ?? '',
        roomId: json['roomId'] as String?,
        name: json['name'] as String? ?? '',
        type: DeviceType.parse(json['type']),
        adapter: json['adapter'] as String? ?? '',
        address: Map<String, dynamic>.from(json['address'] as Map? ?? const {}),
        // Capabilities this version doesn't know are skipped, not an error.
        capabilities: {
          for (final name in json['capabilities'] as List? ?? const [])
            ?Capability.parse(name),
        },
        favourite: json['favourite'] == true,
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      );
}

/// What a device reports right now. Never stored or synced: it is read
/// from the device itself.
@immutable
class DeviceState {
  const DeviceState({this.reachable = true, this.values = const {}});

  /// Not answering: switched off at the wall, out of range, or the phone
  /// is away from home with no hub.
  const DeviceState.unreachable() : reachable = false, values = const {};

  final bool reachable;
  final Map<Capability, Object> values;

  bool? get on => values[Capability.onOff] as bool?;
  num? number(Capability c) => values[c] as num?;

  DeviceState withValue(Capability c, Object value) =>
      DeviceState(reachable: reachable, values: {...values, c: value});
}

/// "Set this capability to this value", sent to a device.
@immutable
class DeviceCommand {
  const DeviceCommand(this.capability, this.value);
  const DeviceCommand.turn(bool on) : capability = Capability.onOff, value = on;

  final Capability capability;
  final Object value;
}
