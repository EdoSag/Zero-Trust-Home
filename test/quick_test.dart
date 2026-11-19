import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_home/l10n/generated/app_l10n_en.dart';
import 'package:zerotrust_home/model/device.dart';
import 'package:zerotrust_home/model/scene.dart';
import 'package:zerotrust_home/quick/quick_snapshot.dart';
import 'package:zerotrust_home/quick/quick_store.dart';
import 'package:zerotrust_home/quick/quick_taps.dart';
import 'package:zerotrust_home/ui/home_page.dart';

import 'support/app.dart';

class FakeVault implements QuickVault {
  String? text;
  var clears = 0;
  QuickTap? tap;
  final tapped = StreamController<void>.broadcast();

  @override
  Future<void> save(String t) async => text = t;
  @override
  Future<String?> load() async => text;
  @override
  Future<void> clear() async {
    clears++;
    text = null;
  }

  @override
  Future<QuickTap?> takeTap() async {
    final t = tap;
    tap = null;
    return t;
  }

  @override
  Stream<void> get taps => tapped.stream;
}

HomeDevice thing(
  String id,
  String name,
  DeviceType type,
  Set<Capability> capabilities, {
  Map<String, dynamic> address = const {},
}) => HomeDevice(
  id: id,
  homeId: 'h1',
  roomId: 'r1',
  name: name,
  type: type,
  adapter: 'fake',
  address: address,
  capabilities: capabilities,
);

final lamp = thing(
  'lamp',
  'Lamp',
  DeviceType.light,
  {Capability.onOff, Capability.brightness},
  address: {'ip': '192.168.1.20', 'localKey': 'secret-key'},
);
final door = thing('door', 'Front door', DeviceType.lock, {Capability.locked});
final blind = thing('blind', 'Blind', DeviceType.blind, {Capability.position});
final sensor = thing('sense', 'Hall sensor', DeviceType.sensor, {
  Capability.temperature,
});
const night = Scene(
  id: 's1',
  homeId: 'h1',
  name: 'Good night',
  actions: [
    SceneAction(deviceId: 'lamp', capability: Capability.onOff, value: false),
    SceneAction(deviceId: 'door', capability: Capability.locked, value: true),
  ],
);

late FakeVault vault;
late FakeAdapter fake;

Future<ProviderContainer> open(WidgetTester tester) async {
  vault = FakeVault();
  fake = FakeAdapter();
  await tester.pumpWidget(
    app(
      const HomePage(),
      homes: const [flat],
      rooms: const [living],
      devices: [lamp, door, blind, sensor],
      scenes: const [night],
      adapters: [fake],
      overrides: [quickVaultProvider.overrideWithValue(vault)],
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(HomePage)));
}

Future<void> settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

void main() {
  test('the copy holds names, never how to reach a device', () {
    final text = QuickSnapshot(
      homes: const [flat],
      rooms: const [living],
      devices: [lamp],
      scenes: const [night],
    ).encode();
    expect(text, isNot(contains('secret-key')));
    expect(text, isNot(contains('192.168.1.20')));
    expect(text, isNot(contains('adapter')));
    final back = QuickSnapshot.decode(text);
    expect(back.homes.single.name, 'Flat');
    expect(back.rooms.single.name, 'Living room');
    expect(back.devices.single.name, 'Lamp');
    expect(back.devices.single.capabilities, lamp.capabilities);
    expect(back.devices.single.roomId, 'r1');
    expect(back.scenes.single.name, 'Good night');
    // Steps of a scene say which devices it touches: not kept either.
    expect(back.scenes.single.actions, isEmpty);
    // Unreadable or another version: empty, never a crash.
    expect(QuickSnapshot.decode('nope').devices, isEmpty);
    expect(QuickSnapshot.decode(null).devices, isEmpty);
    expect(QuickSnapshot.decode('{"version":1}').devices, isEmpty);
  });

  testWidgets('nothing is kept until the switch is on, and it goes when off', (
    tester,
  ) async {
    final container = await open(tester);
    container.read(quickSyncProvider);
    await settle(tester);
    // Off by default.
    expect(vault.text, isNull);

    await container.read(quickControlsOnProvider.notifier).set(true);
    await settle(tester);
    expect(
      QuickSnapshot.decode(vault.text).devices.map((d) => d.name),
      unorderedEquals(['Lamp', 'Front door', 'Blind', 'Hall sensor']),
    );

    await repo.saveDevice(lamp.copyWith(name: 'Desk lamp'));
    await settle(tester);
    expect(
      QuickSnapshot.decode(vault.text).devices.map((d) => d.name),
      contains('Desk lamp'),
    );

    await container.read(quickControlsOnProvider.notifier).set(false);
    await settle(tester);
    expect(vault.text, isNull);
  });

  testWidgets('signing out drops a save waiting to happen', (tester) async {
    final container = await open(tester);
    await container.read(quickControlsOnProvider.notifier).set(true);
    container.read(quickSyncProvider);
    await settle(tester);
    expect(vault.text, isNotNull);
    await repo.saveDevice(lamp.copyWith(name: 'Desk lamp'));
    await tester.pump();
    await container.read(quickClearsProvider.notifier).clear();
    await settle(tester);
    expect(vault.text, isNull);
  });

  group('a tap in the controls panel, after unlocking', () {
    Future<String?> tap(ProviderContainer container, String action, String id) {
      vault.tap = (action: action, id: id);
      return container.read(quickTapsProvider).run(AppL10nEn());
    }

    testWidgets('switches a device the other way', (tester) async {
      final container = await open(tester);
      fake.set('lamp', const DeviceState(values: {Capability.onOff: true}));
      await tester.pumpAndSettle();
      late String? said;
      await tester.runAsync(
        () async => said = await tap(container, 'toggle', 'lamp'),
      );
      expect(said, 'Lamp is off.');
      expect(fake.sent.single.$2.value, false);
      // Taken once.
      expect(await container.read(quickTapsProvider).run(AppL10nEn()), isNull);
    });

    testWidgets('only ever locks a door', (tester) async {
      final container = await open(tester);
      fake.set('door', const DeviceState(values: {Capability.locked: true}));
      late String? said;
      await tester.runAsync(
        () async => said = await tap(container, 'toggle', 'door'),
      );
      expect(said, 'Front door is locked.');
      expect(fake.sent.single.$2.capability, Capability.locked);
      expect(fake.sent.single.$2.value, true);
    });

    testWidgets('opens a closed blind, closes an open one', (tester) async {
      final container = await open(tester);
      fake.set('blind', const DeviceState(values: {Capability.position: 0}));
      await tester.pumpAndSettle();
      late String? said;
      await tester.runAsync(
        () async => said = await tap(container, 'toggle', 'blind'),
      );
      expect(said, 'Blind is open.');
      expect(fake.sent.single.$2.value, 100);
    });

    testWidgets('runs a scene', (tester) async {
      final container = await open(tester);
      late String? said;
      await tester.runAsync(
        () async => said = await tap(container, 'scene', 's1'),
      );
      expect(said, 'Good night is set.');
      expect(fake.sent.map((s) => s.$1), unorderedEquals(['lamp', 'door']));
    });

    testWidgets('says when a device doesn\'t answer', (tester) async {
      final container = await open(tester);
      fake.set('lamp', const DeviceState.unreachable());
      await tester.pumpAndSettle();
      late String? said;
      await tester.runAsync(
        () async => said = await tap(container, 'toggle', 'lamp'),
      );
      expect(said, 'Lamp didn\'t answer.');
      expect(fake.sent, isEmpty);
    });

    testWidgets('a sensor or a deleted device does nothing', (tester) async {
      final container = await open(tester);
      late String? sensorSaid;
      late String? goneSaid;
      await tester.runAsync(() async {
        sensorSaid = await tap(container, 'toggle', 'sense');
        goneSaid = await tap(container, 'toggle', 'gone');
      });
      expect(sensorSaid, isNull);
      expect(goneSaid, isNull);
      expect(fake.sent, isEmpty);
    });
  });
}
