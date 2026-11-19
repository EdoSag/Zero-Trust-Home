import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

import '../adapters/matter/matter_fabric.dart';
import '../model/device.dart';
import '../model/home.dart';

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

  /// The home's Matter fabric, made the first time a Matter device is
  /// added. Throws [MatterFabricUnreadable] rather than replace one this
  /// version can't read: the home's devices only trust the saved key.
  Future<MatterFabric> fabricFor(String homeId) async {
    final saved = await loadFabric(homeId);
    if (saved != null) {
      if (!saved.isUsable) throw const MatterFabricUnreadable();
      return saved;
    }
    final fabric = MatterFabric.create(homeId);
    // Refuses to overwrite an item a newer version of the app wrote.
    await saveFabric(fabric);
    return fabric;
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

  /// Deletes a home with its rooms and devices.
  Future<void> deleteHome(String id) async {
    for (final d in await allDevices()) {
      if (d.homeId == id) await deleteDevice(d.id);
    }
    for (final r in await allRooms()) {
      if (r.homeId == id) await removeRoom(r.id);
    }
    if (await loadFabric(id) != null) await removeFabric(id);
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
