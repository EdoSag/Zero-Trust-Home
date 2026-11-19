import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_home/adapters/homeassistant/ha_adapter.dart';
import 'package:zerotrust_home/adapters/homeassistant/ha_providers.dart';
import 'package:zerotrust_home/adapters/homeassistant/ha_server.dart';
import 'package:zerotrust_home/data/home_store.dart';
import 'package:zerotrust_home/model/device.dart';
import 'package:zerotrust_home/ui/add_device_page.dart';
import 'package:zerotrust_home/ui/ha_add_page.dart';

import '../support/app.dart';
import '../support/fake_ha.dart';

late FakeHa ha;

Widget haApp(
  Widget home, {
  Locale locale = ZtLanguages.english,
  List<HomeDevice> devices = const [],
}) {
  ha = FakeHa(
    states: [
      haState('light.desk', 'off', {
        'friendly_name': 'Desk lamp',
        'supported_color_modes': ['brightness'],
      }),
      haState('switch.tv', 'on', {
        'friendly_name': 'TV plug',
        'device_class': 'outlet',
      }),
      haState('person.edo', 'home'),
    ],
  );
  return app(
    home,
    homes: const [flat],
    rooms: const [living, kitchen],
    devices: devices,
    adapters: [FakeAdapter(id: HomeAssistantAdapter.adapterId)],
    locale: locale,
    overrides: [
      haAdapterProvider.overrideWith(
        (ref) => HomeAssistantAdapter(
          loadServer: (homeId) =>
              ref.read(homeRepositoryProvider).loadHaServer(homeId),
          connect: ha.connect,
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

Future<void> connect(WidgetTester tester, String url, String token) async {
  await tester.enterText(find.byType(TextFormField).at(0), url);
  await tester.enterText(find.byType(TextFormField).at(1), token);
  await tester.ensureVisible(find.widgetWithText(FilledButton, 'Connect'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Home Assistant is a way to add devices', (tester) async {
    phone(tester);
    await tester.pumpWidget(haApp(const AddDevicePage()));
    await tester.pumpAndSettle();
    final row = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Home Assistant'),
        matching: find.byType(ListTile),
      ),
    );
    expect(row.enabled, isTrue);
    await tester.tap(find.text('Home Assistant'));
    await tester.pumpAndSettle();
    expect(find.byType(HaAddPage), findsOneWidget);
  });

  testWidgets('connect once, then pick devices to add', (tester) async {
    phone(tester);
    await tester.pumpWidget(haApp(const HaAddPage()));
    await tester.pumpAndSettle();

    // A wrong token isn't saved.
    await connect(tester, '192.168.1.10', 'nope');
    expect(find.textContaining('didn\'t accept the token'), findsOneWidget);
    expect(repo.haServers, isEmpty);

    await connect(tester, '192.168.1.10', 'good-token');
    expect(ha.uris.last.toString(), 'ws://192.168.1.10:8123/api/websocket');
    final saved = repo.haServers['h1']!;
    expect(saved.url, 'http://192.168.1.10:8123');
    expect(saved.token, 'good-token');
    expect(find.text('Desk lamp'), findsOneWidget);
    expect(find.text('TV plug'), findsOneWidget);
    // Nothing the app can't show.
    expect(find.textContaining('person.edo'), findsNothing);

    await tester.tap(find.text('Desk lamp'));
    await tester.tap(find.text('TV plug'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add 2 devices'));
    await tester.pumpAndSettle();
    final added = {for (final d in repo.devices) d.name: d};
    expect(added.keys, unorderedEquals(['Desk lamp', 'TV plug']));
    expect(added['TV plug']!.type, DeviceType.plug);
    expect(added['Desk lamp']!.address, {'entity': 'light.desk'});
    expect(added['Desk lamp']!.capabilities, {
      Capability.onOff,
      Capability.brightness,
    });
    expect(added['Desk lamp']!.adapter, 'homeassistant');
    expect(ha.open, 0);
  });

  testWidgets('a connected home goes straight to its devices', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      haApp(
        const AddDevicePage(),
        devices: const [
          HomeDevice(
            id: 'd1',
            homeId: 'h1',
            name: 'Desk lamp',
            adapter: 'homeassistant',
            address: {'entity': 'light.desk'},
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    // Made now, as the app would have it already.
    ProviderScope.containerOf(
      tester.element(find.byType(AddDevicePage)),
    ).read(homeRepositoryProvider);
    await repo.saveHaServer(
      const HaServer(
        homeId: 'h1',
        url: 'http://192.168.1.10:8123',
        token: 'good-token',
      ),
    );
    await tester.tap(find.text('Home Assistant'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Connected to http://192.168.1.10:8123'),
      findsOneWidget,
    );
    // Already added: shown ticked, and can't be added twice.
    expect(find.text('Already in this home'), findsOneWidget);
    final desk = tester.widget<CheckboxListTile>(
      find.ancestor(
        of: find.text('Desk lamp'),
        matching: find.byType(CheckboxListTile),
      ),
    );
    expect(desk.value, isTrue);
    expect(desk.onChanged, isNull);
    expect(find.text('Add devices'), findsOneWidget);

    // A new token replaces the old one once it works.
    ha.token = 'new-token';
    await tester.tap(find.byTooltip('Change address or token'));
    await tester.pumpAndSettle();
    await connect(tester, 'http://192.168.1.10:8123', 'new-token');
    expect(repo.haServers['h1']!.token, 'new-token');
    expect(find.text('TV plug'), findsOneWidget);
  });

  testWidgets('says when Home Assistant can\'t be reached', (tester) async {
    phone(tester);
    await tester.pumpWidget(haApp(const HaAddPage()));
    await tester.pumpAndSettle();
    ha.down = true;
    await connect(tester, 'homeassistant.local', 'good-token');
    expect(
      find.textContaining('didn\'t answer at that address'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextFormField).at(0), '');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter an address like'), findsOneWidget);
  });

  testWidgets('Hebrew', (tester) async {
    phone(tester);
    await tester.pumpWidget(
      haApp(const HaAddPage(), locale: ZtLanguages.hebrew),
    );
    await tester.pumpAndSettle();
    expect(find.text('כתובת Home Assistant'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
