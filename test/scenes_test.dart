import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_home/adapters/device_adapter.dart';
import 'package:zerotrust_home/data/home_store.dart';
import 'package:zerotrust_home/model/device.dart';
import 'package:zerotrust_home/model/scene.dart';
import 'package:zerotrust_home/ui/home_page.dart';
import 'package:zerotrust_home/ui/scene_page.dart';

import 'support/app.dart';

HomeDevice thing(
  String id,
  String name,
  DeviceType type,
  Set<Capability> capabilities,
) => HomeDevice(
  id: id,
  homeId: 'h1',
  roomId: 'r1',
  name: name,
  type: type,
  adapter: 'fake',
  capabilities: capabilities,
);

final door = thing('lock', 'Front door', DeviceType.lock, {Capability.locked});
final blind = thing('blind', 'Blind', DeviceType.blind, {Capability.position});
final heater = thing('heat', 'Heating', DeviceType.thermostat, {
  Capability.onOff,
  Capability.temperature,
  Capability.targetTemperature,
});
final lamp = thing('lamp', 'Lamp', DeviceType.light, {
  Capability.onOff,
  Capability.brightness,
});
final sensor = thing('sense', 'Hall sensor', DeviceType.sensor, {
  Capability.temperature,
});

SceneAction act(String device, Capability c, Object v) =>
    SceneAction(deviceId: device, capability: c, value: v);

List<(String, Capability, Object)> asList(Iterable<SceneAction> actions) => [
  for (final a in actions) (a.deviceId, a.capability, a.value),
];

final night = Scene(
  id: 's1',
  homeId: 'h1',
  name: 'Good night',
  actions: [
    act('lamp', Capability.onOff, false),
    act('lock', Capability.locked, true),
    act('blind', Capability.position, 0),
  ],
);

late FakeAdapter fake;

Future<void> open(
  WidgetTester tester, {
  List<Scene> scenes = const [],
  Locale locale = ZtLanguages.english,
}) async {
  tester.view.physicalSize = const Size(360, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  fake = FakeAdapter();
  await tester.pumpWidget(
    app(
      const HomePage(),
      homes: const [flat],
      rooms: const [living],
      devices: [door, blind, heater, lamp, sensor],
      scenes: scenes,
      adapters: [fake],
      locale: locale,
    ),
  );
  fake
    ..set('lock', const DeviceState(values: {Capability.locked: false}))
    ..set('blind', const DeviceState(values: {Capability.position: 40}))
    ..set(
      'heat',
      const DeviceState(
        values: {
          Capability.onOff: true,
          Capability.temperature: 19.5,
          Capability.targetTemperature: 21,
        },
      ),
    )
    ..set(
      'lamp',
      const DeviceState(
        values: {Capability.onOff: true, Capability.brightness: 50},
      ),
    );
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String deviceId, String option) async {
  final menu = find.byKey(ValueKey('choice-$deviceId'));
  await tester.ensureVisible(menu);
  await tester.pumpAndSettle();
  await tester.tap(menu);
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Save');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  group('scene model', () {
    test('saved and read back; unknown steps are left out', () {
      final json = night.toJson();
      final back = Scene.fromJson('s1', json);
      expect(back.name, 'Good night');
      expect(asList(back.actions), asList(night.actions));
      final newer = Scene.fromJson('s2', {
        'homeId': 'h1',
        'name': 'Later',
        'actions': [
          {'device': 'lamp', 'capability': 'sparkle', 'value': true},
          {'device': 'heat', 'capability': 'temperature', 'value': 20},
          {'device': 'lamp', 'capability': 'onOff', 'value': 'yes'},
          {'device': 'lamp', 'capability': 'onOff', 'value': true},
        ],
      });
      expect(asList(newer.actions), [('lamp', Capability.onOff, true)]);
    });

    test('a scene can lock a door but has no way to unlock it', () {
      expect(sceneChoices(door), [SceneChoice.skip, SceneChoice.lock]);
      // Unlocked now: copying leaves the door alone.
      expect(scenePickFrom(door, {Capability.locked: false}), ScenePick.skip);
      expect(
        scenePickFrom(door, {Capability.locked: true}),
        const ScenePick(SceneChoice.lock),
      );
    });

    test('picks turn into steps and back', () {
      void roundTrip(HomeDevice d, ScenePick pick, List<Object> values) {
        final actions = sceneActions(d, pick);
        expect([for (final a in actions) a.value], values);
        final scene = Scene(id: 'x', homeId: 'h1', name: 'x', actions: actions);
        expect(scenePickOf(d, scene), pick);
      }

      roundTrip(lamp, const ScenePick(SceneChoice.on, 30), [true, 30]);
      roundTrip(lamp, const ScenePick(SceneChoice.off), [false]);
      roundTrip(blind, const ScenePick(SceneChoice.open), [100]);
      roundTrip(blind, const ScenePick(SceneChoice.closed), [0]);
      roundTrip(blind, const ScenePick(SceneChoice.part, 25), [25]);
      roundTrip(heater, const ScenePick(SceneChoice.heat, 20.5), [true, 20.5]);
      roundTrip(heater, const ScenePick(SceneChoice.off), [false]);
      expect(sceneChoices(sensor), [SceneChoice.skip]);
      // On first, then how bright.
      expect(
        [
          for (final a in sceneActions(lamp, const ScenePick(SceneChoice.on)))
            a.capability,
        ],
        [Capability.onOff, Capability.brightness],
      );
    });
  });

  testWidgets('make a scene from the Add menu', (tester) async {
    await open(tester);
    // No scenes yet: the row offers one.
    expect(find.widgetWithText(ActionChip, 'Add scene'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Add scene'));
    await tester.pumpAndSettle();
    expect(find.text('New scene'), findsOneWidget);
    // A sensor has nothing to set.
    expect(find.text('Hall sensor'), findsNothing);

    await save(tester);
    expect(find.text('Give the scene a name.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Good night');
    await save(tester);
    expect(find.text('Pick at least one device to change.'), findsOneWidget);

    await choose(tester, 'lamp', 'Off');
    await choose(tester, 'lock', 'Lock');
    await choose(tester, 'heat', 'Set temperature');
    await tester.tap(find.byTooltip('Colder'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Colder'));
    await tester.pumpAndSettle();
    expect(find.text('20°C'), findsOneWidget);
    await save(tester);

    expect(find.byType(ScenePage), findsNothing);
    final scene = repo.scenes.single;
    expect(scene.name, 'Good night');
    expect(scene.homeId, 'h1');
    expect(
      asList(scene.actions),
      unorderedEquals([
        ('lamp', Capability.onOff, false),
        ('lock', Capability.locked, true),
        ('heat', Capability.onOff, true),
        ('heat', Capability.targetTemperature, 20),
      ]),
    );
    expect(find.text('Touch and hold a scene to change it.'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Good night'), findsOneWidget);
    // Nothing was sent while making it.
    expect(fake.sent, isEmpty);
  });

  testWidgets('one tap sets every device in the scene', (tester) async {
    await open(tester, scenes: [night]);
    await tester.tap(find.widgetWithText(ActionChip, 'Good night'));
    await tester.pumpAndSettle();
    expect(
      [for (final (id, c) in fake.sent) (id, c.capability, c.value)],
      unorderedEquals([
        ('lamp', Capability.onOff, false),
        ('lock', Capability.locked, true),
        ('blind', Capability.position, 0),
      ]),
    );
    expect(find.text('Good night is set.'), findsOneWidget);
    expect(find.text('Off'), findsWidgets);
    expect(find.text('Locked'), findsOneWidget);
  });

  testWidgets('says which devices didn\'t answer', (tester) async {
    await open(tester, scenes: [night]);
    fake.failingIds.add('lamp');
    await tester.tap(find.widgetWithText(ActionChip, 'Good night'));
    await tester.pumpAndSettle();
    expect(find.text('Good night: no answer from Lamp.'), findsOneWidget);
    // The others still went.
    expect(fake.sent.map((s) => s.$1), unorderedEquals(['lock', 'blind']));
  });

  testWidgets('a deleted device is skipped; steps go in order', (tester) async {
    await open(
      tester,
      scenes: [
        Scene(
          id: 's2',
          homeId: 'h1',
          name: 'Movie',
          actions: [
            act('gone', Capability.onOff, true),
            act('lamp', Capability.onOff, true),
            act('lamp', Capability.brightness, 20),
          ],
        ),
      ],
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomePage)),
    );
    final failed = await container
        .read(deviceControlProvider)
        .runScene(repo.scenes.single);
    expect(failed, isEmpty);
    expect(
      [for (final (id, c) in fake.sent) (id, c.capability, c.value)],
      [('lamp', Capability.onOff, true), ('lamp', Capability.brightness, 20)],
    );
  });

  testWidgets('copy how things are now', (tester) async {
    await open(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'Add scene'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Evening');
    await tester.tap(find.text('Copy how things are now'));
    await tester.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('Part open'), findsOneWidget);
    await save(tester);
    expect(
      asList(repo.scenes.single.actions),
      unorderedEquals([
        ('lamp', Capability.onOff, true),
        ('lamp', Capability.brightness, 50),
        ('blind', Capability.position, 40),
        ('heat', Capability.onOff, true),
        ('heat', Capability.targetTemperature, 21),
        // The door is unlocked: a scene never unlocks, so it's left alone.
      ]),
    );
  });

  testWidgets('touch and hold to change or delete a scene', (tester) async {
    await open(tester, scenes: [night]);
    await tester.longPress(find.widgetWithText(ActionChip, 'Good night'));
    await tester.pumpAndSettle();
    expect(find.text('Edit scene'), findsOneWidget);
    expect(fake.sent, isEmpty);
    // The saved choices are shown.
    final blindChoice = tester.widget<DropdownButton<SceneChoice>>(
      find.byKey(const ValueKey('choice-blind')),
    );
    expect(blindChoice.value, SceneChoice.closed);

    await tester.enterText(find.byType(TextField), 'Bedtime');
    await choose(tester, 'blind', "Don't change");
    await save(tester);
    expect(repo.scenes.single.name, 'Bedtime');
    expect(repo.scenes.single.id, 's1');
    expect(
      repo.scenes.single.actions.map((a) => a.deviceId),
      ['lock', 'lamp']..sort((a, b) => b.compareTo(a)),
    );

    await tester.longPress(find.widgetWithText(ActionChip, 'Bedtime'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete Bedtime?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repo.scenes, isEmpty);
    expect(find.widgetWithText(ActionChip, 'Add scene'), findsOneWidget);
  });

  testWidgets('deleting a home deletes its scenes', (tester) async {
    await open(tester, scenes: [night]);
    await repo.deleteHome('h1');
    expect(repo.scenes, isEmpty);
  });

  testWidgets('Hebrew scene editor fits', (tester) async {
    await open(tester, scenes: [night], locale: ZtLanguages.hebrew);
    await tester.longPress(find.widgetWithText(ActionChip, 'Good night'));
    await tester.pumpAndSettle();
    expect(find.text('עריכת תרחיש'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
