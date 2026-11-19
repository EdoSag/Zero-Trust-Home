import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_home/adapters/device_adapter.dart';
import 'package:zerotrust_home/app/home_config.dart';
import 'package:zerotrust_home/adapters/matter/matter_fabric.dart';
import 'package:zerotrust_home/data/home_store.dart';
import 'package:zerotrust_home/l10n/l10n.dart';
import 'package:zerotrust_home/model/device.dart';
import 'package:zerotrust_home/model/home.dart';

/// Keeps everything in memory, in place of the encrypted store. Only the
/// single-item saves and deletes are replaced, so the repository's own
/// logic (new homes, deleting a room or a home) is the real one.
class MemoryRepository extends HomeRepository {
  MemoryRepository(
    super.ref, {
    List<Home> homes = const [],
    List<Room> rooms = const [],
    List<HomeDevice> devices = const [],
  }) {
    for (final h in homes) {
      _homes[h.id] = h;
    }
    for (final r in rooms) {
      _rooms[r.id] = r;
    }
    for (final d in devices) {
      _devices[d.id] = d;
    }
  }

  final _homes = <String, Home>{};
  final _rooms = <String, Room>{};
  final _devices = <String, HomeDevice>{};
  final _changes = StreamController<void>.broadcast();

  List<Home> get homes => _homes.values.toList();
  List<Room> get rooms => _rooms.values.toList();
  List<HomeDevice> get devices => _devices.values.toList();

  Stream<List<T>> _watch<T>(List<T> Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  Stream<List<Home>> watchHomes() =>
      _watch(() => homes..sort((a, b) => a.createdAt.compareTo(b.createdAt)));
  Stream<List<Room>> watchRooms() => _watch(() => rooms);
  Stream<List<HomeDevice>> watchDevices() => _watch(() => devices);

  @override
  Future<List<Room>> allRooms() async => rooms;
  @override
  Future<List<HomeDevice>> allDevices() async => devices;

  @override
  Future<void> saveHome(Home h) async {
    _homes[h.id] = h;
    _changes.add(null);
  }

  @override
  Future<void> saveRoom(Room r) async {
    _rooms[r.id] = r;
    _changes.add(null);
  }

  @override
  Future<void> saveDevice(HomeDevice d) async {
    _devices[d.id] = d;
    _changes.add(null);
  }

  final fabrics = <String, MatterFabric>{};

  /// What "syncing" does in a test: nothing, fail, or bring another
  /// phone's items.
  Future<void> Function()? onSync;
  var syncs = 0;

  @override
  Future<void> syncFabrics() async {
    syncs++;
    await onSync?.call();
  }

  @override
  Future<MatterFabric?> loadFabric(String homeId) async => fabrics[homeId];
  @override
  Future<void> saveFabric(MatterFabric f) async => fabrics[f.homeId] = f;
  @override
  Future<void> removeFabric(String homeId) async => fabrics.remove(homeId);

  @override
  Future<void> removeHome(String id) async {
    _homes.remove(id);
    _changes.add(null);
  }

  @override
  Future<void> removeRoom(String id) async {
    _rooms.remove(id);
    _changes.add(null);
  }

  @override
  Future<void> deleteDevice(String id) async {
    _devices.remove(id);
    _changes.add(null);
  }
}

/// Devices that live in memory: they start off, and do what they're told
/// unless [failing].
class FakeAdapter implements DeviceAdapter {
  FakeAdapter({this.id = 'fake'});

  @override
  final String id;
  final _states = <String, DeviceState>{};
  final _changes = StreamController<String>.broadcast();
  final sent = <(String, DeviceCommand)>[];
  bool failing = false;

  DeviceState stateOf(String deviceId) =>
      _states[deviceId] ?? const DeviceState(values: {Capability.onOff: false});

  void set(String deviceId, DeviceState state) {
    _states[deviceId] = state;
    _changes.add(deviceId);
  }

  @override
  Stream<DeviceState> watch(HomeDevice device) async* {
    yield stateOf(device.id);
    yield* _changes.stream
        .where((id) => id == device.id)
        .map((_) => stateOf(device.id));
  }

  @override
  Future<void> send(HomeDevice device, DeviceCommand command) async {
    if (failing) throw StateError('no answer');
    sent.add((device.id, command));
    set(
      device.id,
      stateOf(device.id).withValue(command.capability, command.value),
    );
  }
}

late MemoryRepository repo;

Widget app(
  Widget home, {
  List<Home> homes = const [],
  List<Room> rooms = const [],
  List<HomeDevice> devices = const [],
  List<DeviceAdapter> adapters = const [],
  Locale locale = ZtLanguages.english,
  PreferencesStore? preferences,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      ...overrides,
      ztAppConfigProvider.overrideWithValue(homeAppConfig),
      ztPreferencesStoreProvider.overrideWithValue(
        preferences ?? InMemoryPreferencesStore(),
      ),
      deviceAdaptersProvider.overrideWithValue({
        for (final a in adapters) a.id: a,
      }),
      homeRepositoryProvider.overrideWith(
        (ref) => repo = MemoryRepository(
          ref,
          homes: homes,
          rooms: rooms,
          devices: devices,
        ),
      ),
      homesProvider.overrideWith(
        (ref) => (ref.watch(homeRepositoryProvider) as MemoryRepository)
            .watchHomes(),
      ),
      roomsProvider.overrideWith(
        (ref) => (ref.watch(homeRepositoryProvider) as MemoryRepository)
            .watchRooms(),
      ),
      devicesProvider.overrideWith(
        (ref) => (ref.watch(homeRepositoryProvider) as MemoryRepository)
            .watchDevices(),
      ),
    ],
    child: MaterialApp(
      // The suite's real theme: its full-width buttons break rows that a
      // plain theme lets through.
      theme: ZtTheme.light(accent: homeAppConfig.accent),
      locale: locale,
      supportedLocales: ZtLanguages.supported,
      localizationsDelegates: const [
        AppL10n.delegate,
        ...ZtLanguages.delegates,
      ],
      home: home,
    ),
  );
}

const flat = Home(id: 'h1', name: 'Flat', createdAt: 1);
const living = Room(
  id: 'r1',
  homeId: 'h1',
  name: 'Living room',
  kind: RoomKind.living,
);
const kitchen = Room(
  id: 'r2',
  homeId: 'h1',
  name: 'Kitchen',
  kind: RoomKind.kitchen,
  order: 1,
);

HomeDevice plug({
  String id = 'd1',
  String name = 'Heater plug',
  String? roomId = 'r1',
  String adapter = 'fake',
  bool favourite = false,
}) => HomeDevice(
  id: id,
  homeId: 'h1',
  roomId: roomId,
  name: name,
  type: DeviceType.plug,
  adapter: adapter,
  capabilities: const {Capability.onOff},
  favourite: favourite,
);
