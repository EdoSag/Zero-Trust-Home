import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_home/adapters/hue/hue_adapter.dart';
import 'package:zerotrust_home/adapters/hue/hue_bridge.dart';
import 'package:zerotrust_home/adapters/hue/hue_providers.dart';
import 'package:zerotrust_home/data/home_store.dart';
import 'package:zerotrust_home/model/device.dart';
import 'package:zerotrust_home/ui/add_device_page.dart';
import 'package:zerotrust_home/ui/hue_add_page.dart';

import '../support/app.dart';
import '../support/fake_hue.dart';

late FakeHue hue;

Widget hueApp(
  Widget home, {
  Locale locale = ZtLanguages.english,
  List<HomeDevice> devices = const [],
}) {
  hue = FakeHue(
    lights: [
      hueLight('desk', 'Desk lamp', brightness: 40),
      hueLight('plug', 'Heater', archetype: 'plug'),
    ],
  );
  return app(
    home,
    homes: const [flat],
    rooms: const [living, kitchen],
    devices: devices,
    adapters: [FakeAdapter(id: HueAdapter.adapterId)],
    locale: locale,
    overrides: [
      hueAdapterProvider.overrideWith(
        (ref) => HueAdapter(
          loadBridge: (homeId) =>
              ref.read(homeRepositoryProvider).loadHueBridge(homeId),
          connect: hue.connect,
        ),
      ),
    ],
  );
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Scrolls the list of ways to connect down to Philips Hue.
Future<void> showHue(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Philips Hue'),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> connect(WidgetTester tester, String host) async {
  await tester.enterText(find.byType(TextFormField), host);
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Connect'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Philips Hue is a way to add devices', (tester) async {
    phone(tester);
    await tester.pumpWidget(hueApp(const AddDevicePage()));
    await tester.pumpAndSettle();
    await showHue(tester);
    final row = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Philips Hue'),
        matching: find.byType(ListTile),
      ),
    );
    expect(row.enabled, isTrue);
    await tester.tap(find.text('Philips Hue'));
    await tester.pumpAndSettle();
    expect(find.byType(HueAddPage), findsOneWidget);
    // The address comes first, then the button to press, then Connect.
    final field = tester.getRect(find.byType(TextFormField));
    final press = tester.getRect(find.textContaining('round button'));
    expect(field.left, greaterThanOrEqualTo(0));
    expect(field.right, lessThanOrEqualTo(360));
    expect(press.top, greaterThan(field.top));
    expect(press.right, lessThanOrEqualTo(360));
  });

  testWidgets('press the button, connect, then pick lights to add', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(hueApp(const HueAddPage()));
    await tester.pumpAndSettle();

    await connect(tester, 'not an address');
    expect(find.text('Enter an address like 192.168.1.20'), findsOneWidget);

    // Button not pressed: asked for, and nothing is saved.
    await connect(tester, '192.168.1.20');
    expect(find.textContaining('then tap Connect again'), findsOneWidget);
    expect(repo.hueBridges, isEmpty);

    hue.pressed = true;
    await connect(tester, 'https://192.168.1.20/');
    final saved = repo.hueBridges['h1']!;
    expect(saved.host, '192.168.1.20');
    expect(saved.key, FakeHue.key);
    expect(saved.certificate, FakeHue.certificate);
    expect(find.text('Desk lamp'), findsOneWidget);
    expect(find.text('Heater'), findsOneWidget);

    await tester.tap(find.text('Desk lamp'));
    await tester.tap(find.text('Heater'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add 2 devices'));
    await tester.pumpAndSettle();
    final added = {for (final d in repo.devices) d.name: d};
    expect(added.keys, unorderedEquals(['Desk lamp', 'Heater']));
    expect(added['Heater']!.type, DeviceType.plug);
    expect(added['Desk lamp']!.address, {'light': 'desk'});
    expect(added['Desk lamp']!.capabilities, {
      Capability.onOff,
      Capability.brightness,
    });
    expect(added['Desk lamp']!.adapter, 'hue');
    expect(hue.links.every((l) => l.closed), isTrue);
  });

  testWidgets('a connected home goes straight to its lights', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      hueApp(
        const AddDevicePage(),
        devices: const [
          HomeDevice(
            id: 'd1',
            homeId: 'h1',
            name: 'Desk lamp',
            adapter: 'hue',
            address: {'light': 'desk'},
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    ProviderScope.containerOf(
      tester.element(find.byType(AddDevicePage)),
    ).read(homeRepositoryProvider);
    await repo.saveHueBridge(
      const HueBridge(
        homeId: 'h1',
        host: '192.168.1.20',
        key: FakeHue.key,
        certificate: FakeHue.certificate,
      ),
    );
    await showHue(tester);
    await tester.tap(find.text('Philips Hue'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Connected to the bridge at 192.168.1.20'),
      findsOneWidget,
    );
    expect(find.text('Already in this home'), findsOneWidget);
    final desk = tester.widget<CheckboxListTile>(
      find.ancestor(
        of: find.text('Desk lamp'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    expect(desk.value, isTrue);
    expect(desk.onChanged, isNull);
  });

  testWidgets('says when another bridge answers at the address', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(hueApp(const AddDevicePage()));
    await tester.pumpAndSettle();
    ProviderScope.containerOf(
      tester.element(find.byType(AddDevicePage)),
    ).read(homeRepositoryProvider);
    await repo.saveHueBridge(
      const HueBridge(
        homeId: 'h1',
        host: '192.168.1.20',
        key: FakeHue.key,
        certificate: FakeHue.certificate,
      ),
    );
    hue.shown = 'bb22';
    await showHue(tester);
    await tester.tap(find.text('Philips Hue'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('isn\'t the bridge you connected'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Desk lamp'), findsNothing);
  });

  testWidgets('reads right to left in Hebrew', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      hueApp(const HueAddPage(), locale: ZtLanguages.hebrew),
    );
    await tester.pumpAndSettle();
    expect(find.text('כתובת ה-Bridge'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'התחברות'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
