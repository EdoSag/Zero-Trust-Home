import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_home/adapters/device_adapter.dart';
import 'package:zerotrust_home/adapters/homeassistant/ha_server.dart';
import 'package:zerotrust_home/adapters/matter/matter_fabric.dart';
import 'package:zerotrust_home/model/device.dart';
import 'package:zerotrust_home/model/scene.dart';
import 'package:zerotrust_home/quick/quick_engine.dart';
import 'package:zerotrust_home/quick/quick_snapshot.dart';
import 'package:zerotrust_home/quick/quick_store.dart';
import 'package:zerotrust_home/ui/home_page.dart';

import 'support/app.dart';

class FakeVault implements QuickVault {
  String? text;
  var clears = 0;

  @override
  Future<void> save(String t) async => text = t;
  @override
  Future<String?> load() async => text;
  @override
  Future<void> clear() async {
    clears++;
    text = null;
  }
}

final lamp = HomeDevice(
  id: 'lamp',
  homeId: 'h1',
  roomId: 'r1',
  name: 'Lamp',
  type: DeviceType.light,
  adapter: 'fake',
  capabilities: const {Capability.onOff, Capability.brightness},
);
final door = HomeDevice(
  id: 'door',
  homeId: 'h1',
  roomId: 'r1',
  name: 'Front door',
  type: DeviceType.lock,
  adapter: 'fake',
  capabilities: const {Capability.locked},
);
const night = Scene(
  id: 's1',
  homeId: 'h1',
  name: 'Good night',
  actions: [
    SceneAction(deviceId: 'lamp', capability: Capability.onOff, value: false),
    SceneAction(deviceId: 'door', capability: Capability.locked, value: true),
  ],
);
const server = HaServer(
  homeId: 'h1',
  url: 'http://192.168.1.10:8123',
  token: 'secret',
);

void main() {
  test('the copy reads back as it was written', () {
    final fabric = MatterFabric.create('h1');
    final text = QuickSnapshot(
      homes: const [flat],
      rooms: const [living],
      devices: [lamp],
      scenes: const [night],
      haServers: const [server],
      fabrics: [fabric],
    ).encode();
    final back = QuickSnapshot.decode(text);
    expect(back.homes.single.name, 'Flat');
    expect(back.rooms.single.name, 'Living room');
    expect(back.devices.single.capabilities, lamp.capabilities);
    expect(back.scenes.single.actions, hasLength(2));
    expect(back.haServers.single.token, 'secret');
    expect(back.fabrics.single.toJson(), fabric.toJson());
    // Unreadable or from a newer version: empty, never a crash.
    expect(QuickSnapshot.decode('nope').devices, isEmpty);
    expect(QuickSnapshot.decode(null).devices, isEmpty);
    expect(QuickSnapshot.decode('{"version":99}').devices, isEmpty);
  });

  testWidgets('the app keeps the copy current, and removes it when off', (
    tester,
  ) async {
    final vault = FakeVault();
    await tester.pumpWidget(
      app(
        const HomePage(),
        homes: const [flat],
        rooms: const [living],
        devices: [lamp],
        scenes: const [night],
        adapters: [FakeAdapter()],
        overrides: [quickVaultProvider.overrideWithValue(vault)],
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    await repo.saveHaServer(server);
    container.read(quickSyncProvider);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    var copy = QuickSnapshot.decode(vault.text);
    expect(copy.devices.map((d) => d.name), ['Lamp']);
    expect(copy.scenes.single.name, 'Good night');
    expect(copy.haServers.single.token, 'secret');

    await repo.saveDevice(door);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    copy = QuickSnapshot.decode(vault.text);
    expect(
      copy.devices.map((d) => d.name),
      unorderedEquals(['Lamp', 'Front door']),
    );

    await container.read(quickControlsOnProvider.notifier).set(false);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(vault.text, isNull);
    expect(vault.clears, greaterThan(0));
  });

  testWidgets('signing out while a save is under way leaves nothing', (
    tester,
  ) async {
    final vault = FakeVault();
    await tester.pumpWidget(
      app(
        const HomePage(),
        homes: const [flat],
        devices: [lamp],
        adapters: [FakeAdapter()],
        overrides: [quickVaultProvider.overrideWithValue(vault)],
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    await repo.saveHaServer(server);
    repo.haServerGate = Completer<void>();
    container.read(quickSyncProvider);
    // The save starts, and waits on the token.
    await tester.pump(const Duration(seconds: 2));
    await container.read(quickClearsProvider.notifier).clear();
    repo.haServerGate!.complete();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(vault.text, isNull);
  });

  group('background engine', () {
    late FakeVault vault;
    late FakeAdapter fake;
    late QuickEngine engine;

    setUp(() async {
      vault = FakeVault()
        ..text = QuickSnapshot(
          homes: const [flat],
          devices: [lamp, door],
          scenes: const [night],
        ).encode();
      fake = FakeAdapter()
        ..set(
          'lamp',
          const DeviceState(
            values: {Capability.onOff: true, Capability.brightness: 40},
          ),
        );
      engine = QuickEngine(
        ProviderContainer(
          overrides: [
            ...quickOverrides(),
            quickVaultProvider.overrideWithValue(vault),
            ztPreferencesStoreProvider.overrideWithValue(
              InMemoryPreferencesStore(),
            ),
            deviceAdaptersProvider.overrideWithValue({'fake': fake}),
          ],
        ),
        firstState: const Duration(milliseconds: 200),
      );
      await engine.refresh();
    });

    tearDown(() => engine.container.dispose());

    test('reads states', () async {
      final states =
          await engine.handle('states', {
                'ids': ['lamp', 'gone'],
              })
              as Map;
      expect(states['lamp'], {
        'reachable': true,
        'values': {'onOff': true, 'brightness': 40},
      });
      expect(states['gone'], {
        'reachable': false,
        'values': <String, Object>{},
      });
    });

    test('switches devices and locks', () async {
      expect(
        await engine.handle('send', {
          'id': 'lamp',
          'capability': 'onOff',
          'value': false,
        }),
        isTrue,
      );
      expect(fake.sent.single.$2.value, false);
      expect(
        await engine.handle('send', {
          'id': 'door',
          'capability': 'locked',
          'value': true,
        }),
        isTrue,
      );
      expect(fake.sent.map((s) => s.$1), ['lamp', 'door']);
      // Not something it can set.
      expect(
        await engine.handle('send', {
          'id': 'lamp',
          'capability': 'power',
          'value': 3,
        }),
        isFalse,
      );
      fake.failing = true;
      expect(
        await engine.handle('send', {
          'id': 'lamp',
          'capability': 'onOff',
          'value': true,
        }),
        isFalse,
      );
    });

    test('runs a scene and names who didn\'t answer', () async {
      fake.failingIds.add('door');
      expect(await engine.handle('scene', {'id': 's1'}), ['Front door']);
      expect(fake.sent.single.$1, 'lamp');
    });

    test('tells about changes of watched devices', () async {
      final seen = <String, Object?>{};
      engine.onState = (id, s) => seen[id] = s?.values[Capability.onOff];
      await engine.handle('watch', {
        'ids': ['lamp'],
      });
      await pumpEventQueue();
      expect(seen['lamp'], true);
      fake.set('lamp', const DeviceState(values: {Capability.onOff: false}));
      await pumpEventQueue();
      expect(seen['lamp'], false);
      await engine.handle('unwatch', {});
      fake.set('lamp', const DeviceState(values: {Capability.onOff: true}));
      await pumpEventQueue();
      expect(seen['lamp'], false);
    });

    test('picks up a new copy', () async {
      vault.text = const QuickSnapshot().encode();
      await engine.handle('refresh', {});
      expect(
        await engine.handle('send', {
          'id': 'lamp',
          'capability': 'onOff',
          'value': false,
        }),
        isFalse,
      );
    });
  });
}
