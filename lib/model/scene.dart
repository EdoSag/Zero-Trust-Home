import 'package:flutter/foundation.dart';

import 'device.dart';

/// One step of a scene: set this capability of this device to this value.
@immutable
class SceneAction {
  const SceneAction({
    required this.deviceId,
    required this.capability,
    required this.value,
  });

  final String deviceId;
  final Capability capability;

  /// A `bool` or a `num`, as in a [DeviceCommand].
  final Object value;

  DeviceCommand get command => DeviceCommand(capability, value);

  Map<String, dynamic> toJson() => {
    'device': deviceId,
    'capability': capability.name,
    'value': value,
  };

  /// Null for a step this version can't read (a capability it doesn't
  /// know): the rest of the scene still runs.
  static SceneAction? fromJson(Object? json) {
    if (json is! Map) return null;
    final device = json['device'];
    final capability = Capability.parse(json['capability']);
    final value = json['value'];
    if (device is! String ||
        capability == null ||
        !capability.writable ||
        (value is! bool && value is! num)) {
      return null;
    }
    return SceneAction(
      deviceId: device,
      capability: capability,
      value: value as Object,
    );
  }
}

/// Several devices set at once with one tap: "Good night", "Movie",
/// "Leaving". Saved as a vault item (kind `scene`), like rooms.
@immutable
class Scene {
  const Scene({
    required this.id,
    required this.homeId,
    required this.name,
    this.actions = const [],
    this.order = 0,
  });

  final String id;
  final String homeId;
  final String name;
  final List<SceneAction> actions;

  /// Position among the home's scenes; lower comes first.
  final int order;

  Scene copyWith({String? name, List<SceneAction>? actions, int? order}) =>
      Scene(
        id: id,
        homeId: homeId,
        name: name ?? this.name,
        actions: actions ?? this.actions,
        order: order ?? this.order,
      );

  Map<String, dynamic> toJson() => {
    'homeId': homeId,
    'name': name,
    'actions': [for (final a in actions) a.toJson()],
    'order': order,
  };

  static Scene fromJson(String id, Map<String, dynamic> json) => Scene(
    id: id,
    homeId: json['homeId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    actions: [
      for (final a in json['actions'] as List? ?? const [])
        ?SceneAction.fromJson(a),
    ],
    order: (json['order'] as num?)?.toInt() ?? 0,
  );
}

/// What a scene does with one device, as picked in the scene editor.
enum SceneChoice { skip, on, off, open, closed, part, lock, heat }

@immutable
class ScenePick {
  const ScenePick(this.choice, [this.level]);
  static const skip = ScenePick(SceneChoice.skip);

  final SceneChoice choice;

  /// Brightness or speed (on), position (part) or °C (heat).
  final num? level;

  @override
  bool operator ==(Object other) =>
      other is ScenePick && other.choice == choice && other.level == level;
  @override
  int get hashCode => Object.hash(choice, level);
  @override
  String toString() => 'ScenePick($choice, $level)';
}

/// What a scene can do with [device]. A scene never unlocks a door: only
/// a person at the phone does that, after being asked.
List<SceneChoice> sceneChoices(HomeDevice device) {
  final c = device.capabilities;
  return [
    SceneChoice.skip,
    if (c.contains(Capability.targetTemperature)) ...[
      SceneChoice.heat,
      if (c.contains(Capability.onOff)) SceneChoice.off,
    ] else if (c.contains(Capability.onOff)) ...[
      SceneChoice.on,
      SceneChoice.off,
    ],
    if (c.contains(Capability.position)) ...[
      SceneChoice.open,
      SceneChoice.closed,
      SceneChoice.part,
    ],
    if (c.contains(Capability.locked)) SceneChoice.lock,
  ];
}

/// The capability a choice's level sets on [device], if any.
Capability? sceneLevelOf(HomeDevice device, SceneChoice choice) {
  final c = device.capabilities;
  return switch (choice) {
    SceneChoice.on when c.contains(Capability.brightness) =>
      Capability.brightness,
    SceneChoice.on when c.contains(Capability.fanSpeed) => Capability.fanSpeed,
    SceneChoice.part => Capability.position,
    SceneChoice.heat => Capability.targetTemperature,
    _ => null,
  };
}

/// The level a choice starts at when it is picked.
num sceneDefaultLevel(Capability level) => switch (level) {
  Capability.targetTemperature => 21,
  Capability.position => 50,
  _ => 100,
};

/// The steps that carry out [pick] on [device], in the order to send them.
List<SceneAction> sceneActions(HomeDevice device, ScenePick pick) {
  SceneAction set(Capability c, Object v) =>
      SceneAction(deviceId: device.id, capability: c, value: v);
  final levelOf = sceneLevelOf(device, pick.choice);
  final level = levelOf == null
      ? null
      : (pick.level ?? sceneDefaultLevel(levelOf));
  return switch (pick.choice) {
    SceneChoice.skip => const [],
    SceneChoice.on => [
      set(Capability.onOff, true),
      if (levelOf != null) set(levelOf, level!),
    ],
    SceneChoice.off => [set(Capability.onOff, false)],
    SceneChoice.open => [set(Capability.position, 100)],
    SceneChoice.closed => [set(Capability.position, 0)],
    SceneChoice.part => [set(Capability.position, level!)],
    SceneChoice.lock => [set(Capability.locked, true)],
    SceneChoice.heat => [
      if (device.capabilities.contains(Capability.onOff))
        set(Capability.onOff, true),
      set(Capability.targetTemperature, level!),
    ],
  };
}

/// The pick that matches [values]: a scene's saved steps for the device,
/// or how the device is right now ("copy how things are now").
ScenePick scenePickFrom(HomeDevice device, Map<Capability, Object> values) {
  final c = device.capabilities;
  Object? v(Capability k) => c.contains(k) ? values[k] : null;
  final on = v(Capability.onOff);
  if (c.contains(Capability.targetTemperature)) {
    if (on == false) return const ScenePick(SceneChoice.off);
    final t = v(Capability.targetTemperature);
    if (t is num) return ScenePick(SceneChoice.heat, t);
    return ScenePick.skip;
  }
  if (v(Capability.locked) == true) return const ScenePick(SceneChoice.lock);
  if (on is bool) {
    if (!on) return const ScenePick(SceneChoice.off);
    final levelOf = sceneLevelOf(device, SceneChoice.on);
    final level = levelOf == null ? null : v(levelOf);
    return ScenePick(SceneChoice.on, level is num ? level.round() : null);
  }
  final position = v(Capability.position);
  if (position is num) {
    if (position >= 100) return const ScenePick(SceneChoice.open);
    if (position <= 0) return const ScenePick(SceneChoice.closed);
    return ScenePick(SceneChoice.part, position.round());
  }
  return ScenePick.skip;
}

/// [scenePickFrom] a scene's saved steps for [device].
ScenePick scenePickOf(HomeDevice device, Scene scene) => scenePickFrom(device, {
  for (final a in scene.actions)
    if (a.deviceId == device.id) a.capability: a.value,
});
