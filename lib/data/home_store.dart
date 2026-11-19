import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../adapters/homeassistant/ha_server.dart';
import '../adapters/hue/hue_bridge.dart';
import '../adapters/matter/matter_fabric.dart';
import '../model/device.dart';
import '../model/home.dart';
import '../model/scene.dart';

/// Homes, rooms and devices are items of the Home app, sealed with its own
/// key (`app = 'home'`): `kind` home, room and device. No database change.
final homesCollection = ZtCollection<Home>(
  kind: 'home',
  fromJson: (id, json, _) => Home.fromJson(id, json),
  toJson: (h) => h.toJson(),
  idOf: (h) => h.id,
);

final roomsCollection = ZtCollection<Room>(
  kind: 'room',
  fromJson: (id, json, _) => Room.fromJson(id, json),
  toJson: (r) => r.toJson(),
  idOf: (r) => r.id,
);

final devicesCollection = ZtCollection<HomeDevice>(
  kind: 'device',
  fromJson: (id, json, _) => HomeDevice.fromJson(id, json),
  toJson: (d) => d.toJson(),
  idOf: (d) => d.id,
);

/// Each home's Matter fabric: the keys its Matter devices trust.
final fabricsCollection = ZtCollection<MatterFabric>(
  kind: 'fabric',
  fromJson: (id, json, _) => MatterFabric.fromJson(json),
  toJson: (f) => f.toJson(),
  idOf: (f) => f.id,
);

/// Each home's Home Assistant address and token.
final haServersCollection = ZtCollection<HaServer>(
  kind: 'ha-server',
  fromJson: (id, json, _) => HaServer.fromJson(json),
  toJson: (s) => s.toJson(),
  idOf: (s) => s.id,
);

/// Each home's Hue Bridge: address, key and certificate.
final hueBridgesCollection = ZtCollection<HueBridge>(
  kind: 'hue-bridge',
  fromJson: (id, json, _) => HueBridge.fromJson(json),
  toJson: (b) => b.toJson(),
  idOf: (b) => b.id,
);

/// Scenes: several devices set with one tap.
final scenesCollection = ZtCollection<Scene>(
  kind: 'scene',
  fromJson: (id, json, _) => Scene.fromJson(id, json),
  toJson: (s) => s.toJson(),
  idOf: (s) => s.id,
);

Stream<List<T>> _watch<T>(Ref ref, ZtCollection<T> c) async* {
  final store = await ref.watch(ztLocalStoreProvider.future);
  if (store is ZtLocalStore) {
    yield* c.watch(store);
  } else {
    yield await c.list(store);
  }
}

/// Every home of the account, oldest first.
final homesProvider = StreamProvider<List<Home>>((ref) {
  return _watch(ref, homesCollection).map(
    (l) => [...l]
      ..sort((a, b) {
        final byAge = a.createdAt.compareTo(b.createdAt);
        return byAge != 0 ? byAge : a.id.compareTo(b.id);
      }),
  );
});

/// Every room of every home.
final roomsProvider = StreamProvider<List<Room>>(
  (ref) => _watch(ref, roomsCollection),
);

/// Every device of every home.
final devicesProvider = StreamProvider<List<HomeDevice>>(
  (ref) => _watch(ref, devicesCollection),
);

/// The home picked on this phone (not synced: each phone shows its own).
final selectedHomeIdProvider = NotifierProvider<SelectedHomeId, String?>(
  SelectedHomeId.new,
);

class SelectedHomeId extends Notifier<String?> {
  static const _key = 'home.selected';

  @override
  String? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final saved = await ref.read(ztPreferencesStoreProvider).read(_key);
      // A pick made while loading wins.
      if (saved != null && saved.isNotEmpty && state == null) state = saved;
    } on Object {
      // The first home is shown.
    }
  }

  Future<void> select(String id) async {
    state = id;
    await ref.read(ztPreferencesStoreProvider).write(_key, id);
  }
}

/// The home on screen: the picked one, or the oldest when the pick is gone
/// (deleted on another phone) or nothing was picked. Null with no homes.
final currentHomeProvider = Provider<Home?>((ref) {
  final homes = ref.watch(homesProvider).value ?? const <Home>[];
  if (homes.isEmpty) return null;
  final picked = ref.watch(selectedHomeIdProvider);
  return homes.where((h) => h.id == picked).firstOrNull ?? homes.first;
});

/// The current home's rooms, in order.
final currentRoomsProvider = Provider<List<Room>>((ref) {
  final home = ref.watch(currentHomeProvider);
  final rooms = ref.watch(roomsProvider).value ?? const <Room>[];
  return rooms.where((r) => r.homeId == home?.id).toList()..sort((a, b) {
    final byOrder = a.order.compareTo(b.order);
    return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
  });
});

/// The current home's devices, by name.
final currentDevicesProvider = Provider<List<HomeDevice>>((ref) {
  final home = ref.watch(currentHomeProvider);
  final devices = ref.watch(devicesProvider).value ?? const <HomeDevice>[];
  return devices.where((d) => d.homeId == home?.id).toList()..sort((a, b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.id.compareTo(b.id);
  });
});

/// Every scene of every home.
final scenesProvider = StreamProvider<List<Scene>>(
  (ref) => _watch(ref, scenesCollection),
);

/// The current home's scenes, in order.
final currentScenesProvider = Provider<List<Scene>>((ref) {
  final home = ref.watch(currentHomeProvider);
  final scenes = ref.watch(scenesProvider).value ?? const <Scene>[];
  return scenes.where((s) => s.homeId == home?.id).toList()..sort((a, b) {
    final byOrder = a.order.compareTo(b.order);
    return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
  });
});

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => HomeRepository(ref),
);

/// Saves and deletes through the shared sync controller, so every change is
/// encrypted, stored locally and sent to the account's other devices.
class HomeRepository {
  HomeRepository(this._ref);
  final Ref _ref;

  static const _uuid = Uuid();
  static String newId() => _uuid.v4();

  SyncController get _sync => _ref.read(ztSyncControllerProvider.notifier);
  Future<LocalItemStore> get _store => _ref.read(ztLocalStoreProvider.future);

  Future<List<Room>> allRooms() async => roomsCollection.list(await _store);
  Future<List<HomeDevice>> allDevices() async =>
      devicesCollection.list(await _store);

  Future<void> saveHome(Home h) async =>
      homesCollection.save(_sync, await _store, h);
  Future<void> saveRoom(Room r) async =>
      roomsCollection.save(_sync, await _store, r);
  Future<void> saveDevice(HomeDevice d) async =>
      devicesCollection.save(_sync, await _store, d);

  /// The home's saved Matter fabric, or null when it has none yet.
  Future<MatterFabric?> loadFabric(String homeId) async =>
      fabricsCollection.get(await _store, MatterFabric.itemId(homeId));
  Future<void> saveFabric(MatterFabric f) async =>
      fabricsCollection.save(_sync, await _store, f);
  Future<void> removeFabric(String homeId) =>
      fabricsCollection.delete(_sync, MatterFabric.itemId(homeId));

  /// The home's Home Assistant, or null when it has none.
  Future<HaServer?> loadHaServer(String homeId) async =>
      haServersCollection.get(await _store, HaServer.itemId(homeId));
  Future<void> saveHaServer(HaServer s) async =>
      haServersCollection.save(_sync, await _store, s);
  Future<void> removeHaServer(String homeId) =>
      haServersCollection.delete(_sync, HaServer.itemId(homeId));

  /// The home's Hue Bridge, or null when it has none.
  Future<HueBridge?> loadHueBridge(String homeId) async =>
      hueBridgesCollection.get(await _store, HueBridge.itemId(homeId));
  Future<void> saveHueBridge(HueBridge b) async =>
      hueBridgesCollection.save(_sync, await _store, b);
  Future<void> removeHueBridge(String homeId) =>
      hueBridgesCollection.delete(_sync, HueBridge.itemId(homeId));

  /// Brings this phone up to date with the account and sends what it has
  /// saved. Throws [MatterFabricNeedsSync] when the account can't be
  /// reached.
  Future<void> syncFabrics() async {
    await _sync.syncNow();
    if (_ref.read(ztSyncControllerProvider).error != null) {
      throw const MatterFabricNeedsSync();
    }
  }

  final _fabrics = <String, Future<MatterFabric>>{};

  /// The account's data key for this app, the same on every phone; null
  /// while the vault is locked.
  Uint8List? accountKey() {
    final vault = _ref.read(vaultControllerProvider);
    return vault is VaultUnlocked ? vault.appKey : null;
  }

  /// The home's Matter fabric, made the first time a Matter device is
  /// added. Call it before each device is added.
  ///
  /// A home must have exactly one: devices only trust the key of the fabric
  /// they were added with. Every phone of the account makes the same one
  /// for a home ([MatterFabric.derive]), so two phones adding a first
  /// device at once agree. A fabric that is already saved is used as it
  /// is: homes from before that, made with random keys, keep theirs. Calls
  /// on this phone share one answer while it is worked out, and the
  /// account is asked for its copy each time it can be reached. Throws
  /// [MatterFabricNeedsSync] when a new one can't be checked, and
  /// [MatterFabricUnreadable] rather than replace one this version can't
  /// read.
  Future<MatterFabric> fabricFor(String homeId) {
    final running = _fabrics[homeId];
    if (running != null) return running;
    final made = _fabricFor(homeId);
    _fabrics[homeId] = made;
    // Not remembered: the next call asks the account again.
    made.whenComplete(() => _fabrics.remove(homeId)).ignore();
    return made;
  }

  Future<MatterFabric> _fabricFor(String homeId) async {
    MatterFabric usable(MatterFabric saved) {
      if (!saved.isUsable) throw const MatterFabricUnreadable();
      return saved;
    }

    var saved = await loadFabric(homeId);
    if (saved != null) {
      // The account's copy wins if it changed; offline, the saved one is
      // what every phone had when it last synced.
      try {
        await syncFabrics();
      } on MatterFabricNeedsSync {
        return usable(saved);
      }
      return usable((await loadFabric(homeId)) ?? saved);
    }
    await syncFabrics();
    saved = await loadFabric(homeId);
    if (saved != null) return usable(saved);
    final key = accountKey();
    // Refuses to overwrite an item a newer version of the app wrote.
    await saveFabric(
      key == null
          ? MatterFabric.create(homeId)
          : MatterFabric.derive(homeId, key),
    );
    await syncFabrics();
    // What the account holds now: one from an older version on another
    // phone, made in the same moment, may have won.
    return usable((await loadFabric(homeId))!);
  }

  Future<List<Scene>> allScenes() async => scenesCollection.list(await _store);
  Future<void> saveScene(Scene s) async =>
      scenesCollection.save(_sync, await _store, s);
  Future<void> removeScene(String id) => scenesCollection.delete(_sync, id);

  /// A new scene at the end of its home's.
  Future<Scene> addScene(
    String homeId,
    String name,
    List<SceneAction> actions,
  ) async {
    final last = (await allScenes())
        .where((s) => s.homeId == homeId)
        .fold(-1, (max, s) => s.order > max ? s.order : max);
    final scene = Scene(
      id: newId(),
      homeId: homeId,
      name: name,
      actions: actions,
      order: last + 1,
    );
    await saveScene(scene);
    return scene;
  }

  Future<void> removeHome(String id) => homesCollection.delete(_sync, id);
  Future<void> removeRoom(String id) => roomsCollection.delete(_sync, id);
  Future<void> deleteDevice(String id) => devicesCollection.delete(_sync, id);

  /// A new home with its first rooms, in the order given.
  Future<Home> createHome(
    String name,
    List<({String name, RoomKind kind})> rooms,
  ) async {
    final home = Home(
      id: newId(),
      name: name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await saveHome(home);
    for (final (i, room) in rooms.indexed) {
      await saveRoom(
        Room(
          id: newId(),
          homeId: home.id,
          name: room.name,
          kind: room.kind,
          order: i,
        ),
      );
    }
    return home;
  }

  /// A new room at the end of its home.
  Future<Room> addRoom(String homeId, String name, RoomKind kind) async {
    final last = (await allRooms())
        .where((r) => r.homeId == homeId)
        .fold(-1, (max, r) => r.order > max ? r.order : max);
    final room = Room(
      id: newId(),
      homeId: homeId,
      name: name,
      kind: kind,
      order: last + 1,
    );
    await saveRoom(room);
    return room;
  }

  /// Deletes a room. Its devices stay in the home, without a room.
  Future<void> deleteRoom(String id) async {
    for (final d in await allDevices()) {
      if (d.roomId == id) await saveDevice(d.copyWith(roomId: null));
    }
    await removeRoom(id);
  }

  /// Deletes a home with its rooms, devices and scenes.
  Future<void> deleteHome(String id) async {
    for (final s in await allScenes()) {
      if (s.homeId == id) await removeScene(s.id);
    }
    for (final d in await allDevices()) {
      if (d.homeId == id) await deleteDevice(d.id);
    }
    for (final r in await allRooms()) {
      if (r.homeId == id) await removeRoom(r.id);
    }
    _fabrics.remove(id);
    if (await loadFabric(id) != null) await removeFabric(id);
    if (await loadHaServer(id) != null) await removeHaServer(id);
    if (await loadHueBridge(id) != null) await removeHueBridge(id);
    await removeHome(id);
  }
}

/// The home's Matter keys are saved but this version of the app can't read
/// them.
class MatterFabricUnreadable implements Exception {
  const MatterFabricUnreadable();
  @override
  String toString() => 'MatterFabricUnreadable';
}

/// The home has no Matter keys yet and the account can't be reached to see
/// whether another phone made them. Adding the first Matter device needs a
/// connection once.
class MatterFabricNeedsSync implements Exception {
  const MatterFabricNeedsSync();
  @override
  String toString() => 'MatterFabricNeedsSync';
}
