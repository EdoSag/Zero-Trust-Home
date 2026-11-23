import 'dart:math' as math;

import '../../model/device.dart';

/// A light (or smart plug) on a Hue Bridge, as the bridge lists it.
class HueLight {
  const HueLight({
    required this.id,
    required this.name,
    required this.type,
    required this.capabilities,
  });

  /// The id of the bridge's `light` resource.
  final String id;
  final String name;
  final DeviceType type;
  final Set<Capability> capabilities;

  static HueLight? from(Map<String, dynamic> resource) {
    final id = resource['id'];
    if (resource['type'] != 'light' || id is! String || id.isEmpty) return null;
    final metadata = resource['metadata'];
    final name = metadata is Map ? metadata['name'] : null;
    final archetype = metadata is Map ? metadata['archetype'] : null;
    return HueLight(
      id: id,
      name: name is String && name.isNotEmpty ? name : id,
      type: archetype == 'plug' ? DeviceType.plug : DeviceType.light,
      capabilities: {
        if (resource['on'] is Map) Capability.onOff,
        if (resource['dimming'] is Map) Capability.brightness,
        if (resource['color_temperature'] is Map) Capability.colorTemperature,
        if (resource['color'] is Map) Capability.color,
      },
    );
  }
}

/// The id of the device a resource belongs to (a bulb has a `light` and a
/// `zigbee_connectivity` resource with the same owner).
String? hueOwner(Map<String, dynamic>? resource) {
  final owner = resource?['owner'];
  final rid = owner is Map ? owner['rid'] : null;
  return rid is String ? rid : null;
}

/// What a `light` resource says, as the app's state. [connected] is false
/// when the bridge can't reach the bulb (switched off at the wall).
DeviceState hueRead(Map<String, dynamic>? light, {required bool connected}) {
  if (light == null || !connected) return const DeviceState.unreachable();
  final on = light['on'];
  final dimming = light['dimming'];
  final temperature = light['color_temperature'];
  final color = light['color'];
  final mirek = temperature is Map ? temperature['mirek'] : null;
  final xy = color is Map ? color['xy'] : null;
  return DeviceState(
    values: {
      if (on is Map && on['on'] is bool) Capability.onOff: on['on'] as bool,
      if (dimming is Map && dimming['brightness'] is num)
        Capability.brightness: (dimming['brightness'] as num).round(),
      if (mirek is num && mirek > 0)
        Capability.colorTemperature: (1000000 / mirek).round(),
      if (xy is Map && xy['x'] is num && xy['y'] is num)
        Capability.color: hueXyToRgb(
          (xy['x'] as num).toDouble(),
          (xy['y'] as num).toDouble(),
        ),
    },
  );
}

/// The body of the request that carries out [command], or null when a Hue
/// light can't do it.
Map<String, dynamic>? hueWrite(DeviceCommand command) {
  final value = command.value;
  switch (command.capability) {
    case Capability.onOff when value is bool:
      return {
        'on': {'on': value},
      };
    case Capability.brightness when value is num:
      // A Hue light at 0% is still faintly on: 0 means off.
      if (value <= 0) {
        return {
          'on': {'on': false},
        };
      }
      return {
        'on': {'on': true},
        'dimming': {'brightness': value.clamp(1, 100)},
      };
    case Capability.colorTemperature when value is num && value > 0:
      return {
        'color_temperature': {
          'mirek': (1000000 / value).round().clamp(153, 500),
        },
      };
    case Capability.color when value is int:
      final (x, y) = hueRgbToXy(value);
      return {
        'color': {
          'xy': {'x': x, 'y': y},
        },
      };
    default:
      return null;
  }
}

/// [change] laid over [old]: the bridge reports only the fields that
/// changed, one level deep.
Map<String, dynamic> hueMerge(
  Map<String, dynamic>? old,
  Map<String, dynamic> change,
) {
  final next = <String, dynamic>{...?old};
  for (final MapEntry(:key, :value) in change.entries) {
    final before = next[key];
    next[key] = value is Map && before is Map ? {...before, ...value} : value;
  }
  return next;
}

/// 0xRRGGBB to the CIE xy point Hue lights take (sRGB, D65).
(double, double) hueRgbToXy(int rgb) {
  double linear(int c) {
    final v = c / 255;
    return v > 0.04045
        ? math.pow((v + 0.055) / 1.055, 2.4).toDouble()
        : v / 12.92;
  }

  final r = linear((rgb >> 16) & 0xFF);
  final g = linear((rgb >> 8) & 0xFF);
  final b = linear(rgb & 0xFF);
  final x = r * 0.4124 + g * 0.3576 + b * 0.1805;
  final y = r * 0.2126 + g * 0.7152 + b * 0.0722;
  final z = r * 0.0193 + g * 0.1192 + b * 0.9505;
  final sum = x + y + z;
  // Black has no colour: the white point.
  if (sum <= 0) return (0.3127, 0.3290);
  double round4(double v) => (v * 10000).round() / 10000;
  return (round4(x / sum), round4(y / sum));
}

/// The colour at CIE [x], [y] at full brightness, as 0xRRGGBB.
int hueXyToRgb(double x, double y) {
  if (y <= 0) return 0xFFFFFF;
  final bigX = x / y;
  final bigZ = (1 - x - y) / y;
  var r = bigX * 3.2406 - 1.5372 - bigZ * 0.4986;
  var g = -bigX * 0.9689 + 1.8758 + bigZ * 0.0415;
  var b = bigX * 0.0557 - 0.2040 + bigZ * 1.0570;
  r = math.max(0, r);
  g = math.max(0, g);
  b = math.max(0, b);
  final top = math.max(r, math.max(g, b));
  if (top <= 0) return 0xFFFFFF;
  int channel(double v) {
    final n = v / top;
    final s = n <= 0.0031308 ? 12.92 * n : 1.055 * math.pow(n, 1 / 2.4) - 0.055;
    return (s * 255).round().clamp(0, 255);
  }

  return (channel(r) << 16) | (channel(g) << 8) | channel(b);
}
