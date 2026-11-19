import 'dart:convert';

import '../adapters/homeassistant/ha_server.dart';
import '../adapters/matter/matter_fabric.dart';
import '../model/device.dart';
import '../model/home.dart';
import '../model/scene.dart';

/// What the quick controls (the Android Device Controls panel) need to
/// show and switch devices without the app open: the account's devices and
/// scenes, and how to reach them (Home Assistant tokens, Matter keys).
///
/// It is kept only on this phone, sealed with a key in the Android
/// Keystore, and only while the person has quick controls on. It is never
/// sent anywhere.
class QuickSnapshot {
  const QuickSnapshot({
    this.homes = const [],
    this.rooms = const [],
    this.devices = const [],
    this.scenes = const [],
    this.haServers = const [],
    this.fabrics = const [],
  });

  final List<Home> homes;
  final List<Room> rooms;
  final List<HomeDevice> devices;
  final List<Scene> scenes;
  final List<HaServer> haServers;
  final List<MatterFabric> fabrics;

  /// Version of the layout below; a newer one is read as empty.
  static const version = 1;

  String encode() => jsonEncode({
    'version': version,
    'homes': [
      for (final h in homes) {'id': h.id, ...h.toJson()},
    ],
    'rooms': [
      for (final r in rooms) {'id': r.id, ...r.toJson()},
    ],
    'devices': [
      for (final d in devices) {'id': d.id, ...d.toJson()},
    ],
    'scenes': [
      for (final s in scenes) {'id': s.id, ...s.toJson()},
    ],
    'haServers': [for (final s in haServers) s.toJson()],
    'fabrics': [for (final f in fabrics) f.toJson()],
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
        haServers: each('haServers', (_, j) => HaServer.fromJson(j)),
        fabrics: each('fabrics', (_, j) => MatterFabric.fromJson(j)),
      );
    } on Object {
      return const QuickSnapshot();
    }
  }
}
