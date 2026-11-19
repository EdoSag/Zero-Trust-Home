import '../../model/device.dart';
import 'ha_client.dart';

/// What the app makes of one Home Assistant entity.
class HaEntity {
  const HaEntity({
    required this.id,
    required this.name,
    required this.type,
    required this.capabilities,
  });

  /// `light.kitchen`.
  final String id;
  final String name;
  final DeviceType type;
  final Set<Capability> capabilities;

  String get domain => id.split('.').first;

  /// Null for entities the app has no use for (automations, people,
  /// weather, the sun...), and for sensors it can't show.
  static HaEntity? from(HaState state) {
    final id = state['entity_id'];
    if (id is! String || !id.contains('.')) return null;
    final attributes = _attributes(state);
    final name = (attributes['friendly_name'] as String?)?.trim();
    final shape = _shape(id.split('.').first, attributes);
    if (shape == null) return null;
    return HaEntity(
      id: id,
      name: name == null || name.isEmpty ? id : name,
      type: shape.$1,
      capabilities: shape.$2,
    );
  }
}

Map<String, dynamic> _attributes(HaState state) {
  final a = state['attributes'];
  return a is Map ? Map<String, dynamic>.from(a) : const {};
}

// Light colour modes, as Home Assistant names them.
const _brightnessModes = {
  'brightness',
  'color_temp',
  'hs',
  'xy',
  'rgb',
  'rgbw',
  'rgbww',
  'white',
};
const _colorModes = {'hs', 'xy', 'rgb', 'rgbw', 'rgbww'};

// Cover and fan feature bits.
const _coverSetPosition = 4;
const _fanSetSpeed = 1;

(DeviceType, Set<Capability>)? _shape(
  String domain,
  Map<String, dynamic> attributes,
) {
  final deviceClass = attributes['device_class'];
  final features = (attributes['supported_features'] as num?)?.toInt() ?? 0;
  switch (domain) {
    case 'light':
      final modes = {
        for (final m
            in attributes['supported_color_modes'] as List? ?? const [])
          '$m',
      };
      return (
        DeviceType.light,
        {
          Capability.onOff,
          if (modes.any(_brightnessModes.contains)) Capability.brightness,
          if (modes.contains('color_temp')) Capability.colorTemperature,
          if (modes.any(_colorModes.contains)) Capability.color,
        },
      );
    case 'switch':
      return (
        deviceClass == 'outlet' ? DeviceType.plug : DeviceType.wallSwitch,
        {Capability.onOff},
      );
    case 'input_boolean':
      return (DeviceType.wallSwitch, {Capability.onOff});
    case 'fan':
      return (
        DeviceType.fan,
        {
          Capability.onOff,
          if (features & _fanSetSpeed != 0) Capability.fanSpeed,
        },
      );
    case 'cover':
      // Covers without a set position still open and close: 0 or 100.
      return (DeviceType.blind, {Capability.position});
    case 'lock':
      return (DeviceType.lock, {Capability.locked});
    case 'climate':
      return (
        DeviceType.thermostat,
        {
          Capability.onOff,
          Capability.temperature,
          Capability.targetTemperature,
        },
      );
    case 'binary_sensor':
      return switch (deviceClass) {
        'door' ||
        'window' ||
        'opening' ||
        'garage_door' => (DeviceType.sensor, {Capability.contact}),
        'motion' ||
        'occupancy' ||
        'presence' => (DeviceType.sensor, {Capability.motion}),
        _ => null,
      };
    case 'sensor':
      final capability = switch (deviceClass) {
        'temperature' => Capability.temperature,
        'humidity' => Capability.humidity,
        'battery' => Capability.battery,
        'power' => Capability.power,
        'energy' => Capability.energy,
        _ => null,
      };
      return capability == null ? null : (DeviceType.sensor, {capability});
  }
  return null;
}

/// The app's values for an entity's state. Unreachable while Home
/// Assistant can't reach the device.
DeviceState haRead(HaState? state) {
  if (state == null) return const DeviceState.unreachable();
  final id = state['entity_id'] as String? ?? '';
  final value = state['state'];
  if (value == 'unavailable' || value == null) {
    return const DeviceState.unreachable();
  }
  final a = _attributes(state);
  final deviceClass = a['device_class'];
  final values = <Capability, Object>{};
  num? number(Object? v) => v is num ? v : num.tryParse('$v');
  switch (id.split('.').first) {
    case 'light':
      values[Capability.onOff] = value == 'on';
      final brightness = number(a['brightness']);
      if (brightness != null) {
        values[Capability.brightness] = (brightness / 255 * 100).round();
      }
      final kelvin = number(a['color_temp_kelvin']);
      if (kelvin != null) values[Capability.colorTemperature] = kelvin;
      final rgb = a['rgb_color'];
      if (rgb is List && rgb.length == 3 && rgb.every((c) => c is num)) {
        final [r, g, b] = [for (final c in rgb) (c as num).toInt() & 0xff];
        values[Capability.color] = r << 16 | g << 8 | b;
      }
    case 'switch' || 'input_boolean':
      values[Capability.onOff] = value == 'on';
    case 'fan':
      values[Capability.onOff] = value == 'on';
      final percentage = number(a['percentage']);
      if (percentage != null) values[Capability.fanSpeed] = percentage;
    case 'cover':
      final position = number(a['current_position']);
      values[Capability.position] =
          position ??
          switch (value) {
            'closed' => 0,
            _ => 100,
          };
    case 'lock':
      if (value == 'locked' || value == 'unlocked') {
        values[Capability.locked] = value == 'locked';
      }
    case 'climate':
      values[Capability.onOff] = value != 'off';
      final current = number(a['current_temperature']);
      final target = number(a['temperature']);
      final fahrenheit = a['temperature_unit'] == '°F';
      if (current != null) {
        values[Capability.temperature] = fahrenheit
            ? _celsius(current)
            : current;
      }
      if (target != null) {
        values[Capability.targetTemperature] = fahrenheit
            ? _celsius(target)
            : target;
      }
    case 'binary_sensor':
      final on = value == 'on';
      switch (deviceClass) {
        case 'door' || 'window' || 'opening' || 'garage_door':
          values[Capability.contact] = on;
        case 'motion' || 'occupancy' || 'presence':
          values[Capability.motion] = on;
      }
    case 'sensor':
      final reading = number(value);
      if (reading == null) break;
      final unit = a['unit_of_measurement'];
      switch (deviceClass) {
        case 'temperature':
          values[Capability.temperature] = unit == '°F'
              ? _celsius(reading)
              : reading;
        case 'humidity':
          values[Capability.humidity] = reading;
        case 'battery':
          values[Capability.battery] = reading;
        case 'power':
          values[Capability.power] = unit == 'kW' ? reading * 1000 : reading;
        case 'energy':
          values[Capability.energy] = unit == 'Wh' ? reading / 1000 : reading;
      }
  }
  return DeviceState(values: values);
}

num _celsius(num f) => ((f - 32) * 5 / 9 * 10).round() / 10;

/// The service call for [command]: (domain, service, data). Null when the
/// entity can't do it.
(String, String, Map<String, dynamic>)? haWrite(
  String entityId,
  DeviceCommand command,
  HaState? state,
) {
  final domain = entityId.split('.').first;
  final value = command.value;
  final fahrenheit =
      state != null && _attributes(state)['temperature_unit'] == '°F';
  switch ((domain, command.capability)) {
    case (
          'light' || 'switch' || 'input_boolean' || 'fan' || 'climate',
          Capability.onOff,
        )
        when value is bool:
      return (domain, value ? 'turn_on' : 'turn_off', const {});
    case ('light', Capability.brightness) when value is num:
      final percent = value.clamp(0, 100).round();
      return percent == 0
          ? ('light', 'turn_off', const {})
          : ('light', 'turn_on', {'brightness_pct': percent});
    case ('light', Capability.colorTemperature) when value is num:
      return ('light', 'turn_on', {'color_temp_kelvin': value.round()});
    case ('light', Capability.color) when value is int:
      return (
        'light',
        'turn_on',
        {
          'rgb_color': [value >> 16 & 0xff, value >> 8 & 0xff, value & 0xff],
        },
      );
    case ('fan', Capability.fanSpeed) when value is num:
      return (
        'fan',
        'set_percentage',
        {'percentage': value.clamp(0, 100).round()},
      );
    case ('cover', Capability.position) when value is num:
      final position = value.clamp(0, 100).round();
      final features =
          (_attributes(state ?? const {})['supported_features'] as num?)
              ?.toInt() ??
          0;
      if (features & _coverSetPosition != 0) {
        return ('cover', 'set_cover_position', {'position': position});
      }
      return ('cover', position > 0 ? 'open_cover' : 'close_cover', const {});
    case ('lock', Capability.locked) when value is bool:
      return ('lock', value ? 'lock' : 'unlock', const {});
    case ('climate', Capability.targetTemperature) when value is num:
      final degrees = fahrenheit ? value * 9 / 5 + 32 : value;
      return (
        'climate',
        'set_temperature',
        {'temperature': (degrees * 10).round() / 10},
      );
  }
  return null;
}
