import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_home/l10n/generated/app_l10n_en.dart';
import 'package:zerotrust_home/model/device.dart';
import 'package:zerotrust_home/ui/device_controls.dart';
import 'package:zerotrust_home/ui/home_page.dart';

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
  Capability.humidity,
  Capability.battery,
});

late FakeAdapter fake;

Future<void> open(
  WidgetTester tester, {
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
      adapters: [fake],
      locale: locale,
    ),
  );
  fake
    ..set('lock', const DeviceState(values: {Capability.locked: true}))
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
    )
    ..set(
      'sense',
      const DeviceState(
        values: {
          Capability.temperature: 22.4,
          Capability.humidity: 51.2,
          Capability.battery: 80,
        },
      ),
    );
  await tester.pumpAndSettle();
}

Future<void> details(WidgetTester tester, String name) async {
  await tester.longPress(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  test('tiles say what each device is doing', () {
    final l = AppL10nEn();
    String say(HomeDevice d, Map<Capability, Object> v) =>
        deviceSummary(l, d, DeviceState(values: v));
    expect(
      say(lamp, {Capability.onOff: true, Capability.power: 12.34}),
      'On · 12.3 W',
    );
    expect(say(lamp, {Capability.onOff: false, Capability.power: 0}), 'Off');
    expect(say(door, {Capability.locked: false}), 'Unlocked');
    expect(say(blind, {Capability.position: 0}), 'Closed');
    expect(say(blind, {Capability.position: 100}), 'Open');
    expect(say(blind, {Capability.position: 35}), 'Open 35%');
    expect(
      say(heater, {
        Capability.onOff: true,
        Capability.temperature: 19.5,
        Capability.targetTemperature: 21,
      }),
      'On · 19.5°C · set to 21°C',
    );
    // Off: what it would heat to doesn't matter.
    expect(
      say(heater, {
        Capability.onOff: false,
        Capability.temperature: 19.5,
        Capability.targetTemperature: 21,
      }),
      'Off · 19.5°C',
    );
    expect(
      say(sensor, {
        Capability.temperature: 22.4,
        Capability.humidity: 51.2,
        Capability.battery: 80,
      }),
      '22.4°C · 51%',
    );
    expect(say(sensor, {Capability.battery: 80}), 'Battery 80%');
    expect(say(sensor, {Capability.contact: true}), 'Open');
    expect(say(sensor, {Capability.motion: false}), 'No motion');
  });

  testWidgets('a lock opens its details, and unlocking asks first', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Locked'), findsOneWidget);
    // A tap on a lock never unlocks it.
    await tester.tap(find.text('Front door'));
    await tester.pumpAndSettle();
    expect(fake.sent, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock Front door?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fake.sent, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(fake.sent.single.$2.value, false);
    // Locking needs no question.
    await tester.tap(find.widgetWithText(FilledButton, 'Lock'));
    await tester.pumpAndSettle();
    expect(fake.sent.last.$2.capability, Capability.locked);
    expect(fake.sent.last.$2.value, true);
  });

  testWidgets('a blind opens, closes and goes to a position', (tester) async {
    await open(tester);
    expect(find.text('Open 40%'), findsOneWidget);
    await details(tester, 'Blind');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Close'));
    await tester.pumpAndSettle();
    expect(fake.sent.last.$2.value, 0);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Open'));
    await tester.pumpAndSettle();
    expect(fake.sent.last.$2.value, 100);
    // Dragged to the far left: closed.
    await tester.drag(find.byType(Slider), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(fake.sent.last.$2.capability, Capability.position);
    expect(fake.sent.last.$2.value, 0);
  });

  testWidgets('a thermostat goes warmer and colder', (tester) async {
    await open(tester);
    expect(find.text('On · 19.5°C · set to 21°C'), findsOneWidget);
    await details(tester, 'Heating');
    await tester.tap(find.byTooltip('Warmer'));
    await tester.pumpAndSettle();
    expect(fake.sent.last.$2.value, 21.5);
    await tester.tap(find.byTooltip('Colder'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Colder'));
    await tester.pumpAndSettle();
    expect(fake.sent.last.$2.value, 20.5);
    expect(find.text('Temperature'), findsOneWidget);
  });

  testWidgets('a light dims', (tester) async {
    await open(tester);
    await details(tester, 'Lamp');
    expect(find.text('50%'), findsWidgets);
    await tester.drag(find.byType(Slider), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(fake.sent.last.$2.capability, Capability.brightness);
    expect(fake.sent.last.$2.value, 100);
  });

  testWidgets('a sensor shows its readings', (tester) async {
    await open(tester);
    expect(find.text('22.4°C · 51%'), findsOneWidget);
    await details(tester, 'Hall sensor');
    expect(find.text('Humidity'), findsOneWidget);
    expect(find.text('Battery'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
  });

  testWidgets('Hebrew controls fit', (tester) async {
    await open(tester, locale: ZtLanguages.hebrew);
    await details(tester, 'Heating');
    expect(find.text('מכוון ל'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
