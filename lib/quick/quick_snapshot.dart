import 'dart:convert';

import '../model/device.dart';
import '../model/home.dart';
import '../model/scene.dart';

/// What the phone's controls panel and the home screen widget may show
/// while ZT Home is locked: the names of homes, rooms, devices and scenes,
/// and what kind of device each is. Never how to reach a device (no
/// addresses, local keys, tokens or Matter keys): those stay in the vault,
/// so a tap there opens the app, which carries it out once unlocked.
///
/// Kept only on this phone, sealed with a key in the Android Keystore,
/// and only while "Show devices outside the app" is on.
class QuickSnapshot {
  const QuickSnapshot({
    this.homes = const [],
    this.rooms = const [],
    this.devices = const [],
    this.scenes = const [],
  });

  final List<Home> homes;
  final List<Room> rooms;
  final List<HomeDevice> devices;
  final List<Scene> scenes;

  /// Version of the layout below; any other is read as empty.
  static const version = 2;

  String encode() => jsonEncode({
    'version': version,
    'homes': [
      for (final h in homes) {'id': h.id, 'name': h.name},
    ],
    'rooms': [
      for (final r in rooms) {'id': r.id, 'homeId': r.homeId, 'name': r.name},
    ],
    'devices': [
      for (final d in devices)
        {
          'id': d.id,
          'homeId': d.homeId,
          if (d.roomId != null) 'roomId': d.roomId,
          'name': d.name,
          'type': d.type.name,
          'capabilities': [for (final c in d.capabilities) c.name],
          'favourite': d.favourite,
        },
    ],
    'scenes': [
      for (final s in scenes) {'id': s.id, 'homeId': s.homeId, 'name': s.name},
    ],
  });

  /// Never throws: anything unreadable comes back empty.
  static QuickSnapshot decode(String? text) {
    try {
      final json = jsonDecode(text ?? '') as Map<String, dynamic>;
      if (json['version'] != version) return const QuickSnapshot();
      List<T> each<T>(String key, T Function(String, Map<String, dynamic>) f) =>
          [
            for (final item in json[key] as List? ?? const [])
              if (item is Map<String, dynamic>)
                f(item['id'] as String? ?? '', item),
          ];
      return QuickSnapshot(
        homes: each('homes', Home.fromJson),
        rooms: each('rooms', Room.fromJson),
        devices: each('devices', HomeDevice.fromJson),
        scenes: each('scenes', Scene.fromJson),
      );
    } on Object {
      return const QuickSnapshot();
    }
  }
}
