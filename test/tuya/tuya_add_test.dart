import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_home/adapters/tuya/tuya_adapter.dart';
import 'package:zerotrust_home/adapters/tuya/tuya_codec.dart';
import 'package:zerotrust_home/adapters/tuya/tuya_link.dart';
import 'package:zerotrust_home/adapters/tuya/tuya_providers.dart';
import 'package:zerotrust_home/model/device.dart';
import 'package:zerotrust_home/ui/add_device_page.dart';
import 'package:zerotrust_home/ui/home_page.dart';
import 'package:zerotrust_home/ui/tuya_add_page.dart';

import '../support/app.dart';

/// Pairs without a network: answers the way a plug with power metering
/// would, or fails with [failure].
class FakePairing extends TuyaAdapter {
  TuyaFailure? failure;
  final asked =
      <({String ip, String deviceId, String key, TuyaVersion version})>[];

  @override
  Future<HomeDevice> pair({
    required String id,
    required String homeId,
    required String? roomId,
    required String name,
    required String deviceId,
    required String ip,
    required TuyaVersion version,
    required String localKey,
  }) async {
    asked.add((ip: ip, deviceId: deviceId, key: localKey, version: version));
    if (failure != null) throw TuyaException(failure!);
    final address = TuyaAddress(
      deviceId: deviceId,
      localKey: localKey,
      ip: ip,
      version: version,
      onOffDp: '1',
      powerDp: '19',
    );
    return HomeDevice(
      id: id,
      homeId: homeId,
      roomId: roomId,
      name: name,
      type: DeviceType.plug,
      adapter: TuyaAdapter.adapterId,
      address: address.toJson(),
      capabilities: address.capabilities,
    );
  }
}

const kettle = TuyaAnnouncement(
  deviceId: 'bf1234567890abcdefghij',
  ip: '192.168.1.50',
  versionText: '3.4',
);
const old = TuyaAnnouncement(
  deviceId: 'old1234567890',
  ip: '192.168.1.60',
  versionText: '3.1',
);

late FakePairing pairing;

Widget tuyaApp(
  Widget home, {
  List<TuyaAnnouncement> found = const [kettle, old],
  List<HomeDevice> devices = const [],
  Locale locale = ZtLanguages.english,
}) {
  pairing = FakePairing();
  return app(
    home,
    homes: const [flat],
    rooms: const [living, kitchen],
    devices: devices,
    adapters: [FakeAdapter(id: 'tuya')],
    locale: locale,
    overrides: [
      tuyaAdapterProvider.overrideWithValue(pairing),
      tuyaFoundProvider.overrideWith(
        (ref) => Stream.value({for (final f in found) f.deviceId: f}),
      ),
    ],
  );
}

/// The search spinner never rests, so `pumpAndSettle` would not return.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

ListTile rowOf(WidgetTester tester, String title) => tester.widget<ListTile>(
  find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
);

void main() {
  testWidgets('Tuya is a way to add a device, and lists what it found', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(tuyaApp(const AddDevicePage()));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Tuya / Smart Life'), 200);
    expect(rowOf(tester, 'Tuya / Smart Life').enabled, isTrue);
    await tester.tap(find.text('Tuya / Smart Life'));
    await settle(tester);

    expect(find.byType(TuyaAddPage), findsOneWidget);
    expect(rowOf(tester, 'Device at 192.168.1.50').enabled, isTrue);
    expect(find.text('ID ending in ghij · protocol 3.4'), findsOneWidget);
    // A device this version can't talk to is listed, greyed out.
    expect(rowOf(tester, 'Device at 192.168.1.60').enabled, isFalse);
    expect(find.text("Protocol 3.1 isn't supported yet"), findsOneWidget);
    expect(find.text('Looking for devices on your Wi-Fi…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a device that is already added can\'t be added twice', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      tuyaApp(
        const TuyaAddPage(),
        devices: [
          HomeDevice(
            id: 'd9',
            homeId: 'h1',
            name: 'Kettle',
            adapter: 'tuya',
            address: {'deviceId': kettle.deviceId},
          ),
        ],
      ),
    );
    await settle(tester);
    expect(rowOf(tester, 'Device at 192.168.1.50').enabled, isFalse);
    expect(find.text('Already added'), findsOneWidget);
  });

  testWidgets('pairing a found plug saves it and returns to the home', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(tuyaApp(const HomePage()));
    await settle(tester);
    await tester.tap(find.text('Add a device').first);
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Tuya / Smart Life'), 200);
    await tester.tap(find.text('Tuya / Smart Life'));
    await settle(tester);
    await tester.tap(find.text('Device at 192.168.1.50'));
    await settle(tester);

    expect(find.byType(TuyaPairPage), findsOneWidget);
    // Found on the network: nothing to type but the name and the key.
    expect(find.text('IP address'), findsNothing);
    expect(find.text('Device ID'), findsNothing);

    await tester.enterText(find.byType(TextFormField).first, 'Kettle');
    await tester.tap(find.text('Connect'));
    await settle(tester);
    expect(find.text('A local key has 16 characters.'), findsOneWidget);
    expect(pairing.asked, isEmpty);

    await tester.tap(find.text('Not in a room'));
    await settle(tester);
    await tester.tap(find.text('Kitchen').last);
    await settle(tester);
    await tester.enterText(find.byType(TextFormField).last, '0123456789abcdef');
    await tester.tap(find.text('Connect'));
    await settle(tester);

    expect(pairing.asked.single, (
      ip: '192.168.1.50',
      deviceId: kettle.deviceId,
      key: '0123456789abcdef',
      version: TuyaVersion.v34,
    ));
    final saved = repo.devices.single;
    expect(saved.name, 'Kettle');
    expect(saved.roomId, 'r2');
    expect(saved.adapter, 'tuya');
    expect(saved.capabilities, {Capability.onOff, Capability.power});
    expect(TuyaAddress.parse(saved.address)!.localKey, '0123456789abcdef');

    // Back on the home, with the new device on it.
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.byType(TuyaPairPage), findsNothing);
    expect(find.byType(AddDevicePage), findsNothing);
    expect(find.text('Kettle added'), findsOneWidget);
    expect(find.text('Kettle'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a wrong key and a silent device get their own message', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(tuyaApp(const TuyaPairPage(found: kettle)));
    await settle(tester);
    await tester.enterText(find.byType(TextFormField).last, 'ffffffffffffffff');

    pairing.failure = TuyaFailure.keyRejected;
    await tester.tap(find.text('Connect'));
    await settle(tester);
    expect(find.textContaining("didn't accept this key"), findsOneWidget);
    expect(repo.devices, isEmpty);

    pairing.failure = TuyaFailure.unreachable;
    await tester.tap(find.text('Connect'));
    await settle(tester);
    expect(find.textContaining('No answer from 192.168.1.50'), findsOneWidget);
    expect(find.textContaining("didn't accept this key"), findsNothing);
    expect(repo.devices, isEmpty);
    // Still on the page, ready for another try.
    expect(find.byType(TuyaPairPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('by hand: address, id and version are asked for', (tester) async {
    phone(tester);
    await tester.pumpWidget(tuyaApp(const TuyaAddPage(), found: const []));
    await settle(tester);
    await tester.tap(find.text('Enter the address by hand'));
    await settle(tester);

    await tester.enterText(find.byType(TextFormField).last, '0123456789abcdef');
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await settle(tester);
    expect(find.text('Required'), findsNWidgets(2));
    expect(pairing.asked, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'IP address'),
      ' 10.0.0.8 ',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Device ID'),
      'abc123',
    );
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await settle(tester);
    expect(pairing.asked.single.ip, '10.0.0.8');
    expect(pairing.asked.single.deviceId, 'abc123');
    expect(repo.devices.single.name, 'Smart plug');
    expect(tester.takeException(), isNull);
  });

  testWidgets('the key help shows the Device ID to look up', (tester) async {
    phone(tester);
    await tester.pumpWidget(tuyaApp(const TuyaPairPage(found: kettle)));
    await settle(tester);
    await tester.tap(find.text('Where do I find the local key?'));
    await settle(tester);
    expect(find.text('Finding the local key'), findsOneWidget);
    expect(find.text(kettle.deviceId), findsOneWidget);
    expect(find.textContaining('iot.tuya.com'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await settle(tester);
    expect(find.text('Finding the local key'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hebrew: the pages fit a phone and read right to left', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      tuyaApp(const TuyaAddPage(), locale: ZtLanguages.hebrew),
    );
    await settle(tester);
    expect(find.text('מכשיר בכתובת 192.168.1.50'), findsOneWidget);
    // Right to left: the row's icon is to the right of its title.
    final icon = tester.getCenter(find.byIcon(Icons.power_outlined).first);
    final title = tester.getCenter(find.text('מכשיר בכתובת 192.168.1.50'));
    expect(icon.dx, greaterThan(title.dx));
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('מכשיר בכתובת 192.168.1.50'));
    await settle(tester);
    expect(find.text('חיבור המכשיר'), findsOneWidget);
    expect(find.text('שקע חכם'), findsOneWidget);
    await tester.tap(find.text('איפה מוצאים את המפתח המקומי?'));
    await settle(tester);
    expect(find.text('איך מוצאים את המפתח המקומי'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a plug shows what it draws while it is on', (tester) async {
    phone(tester);
    final adapter = FakeAdapter()
      ..set(
        'd1',
        const DeviceState(
          values: {Capability.onOff: true, Capability.power: 12.34},
        ),
      );
    await tester.pumpWidget(
      app(
        const HomePage(),
        homes: const [flat],
        rooms: const [living],
        devices: [plug()],
        adapters: [adapter],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('On · 12.3 W'), findsOneWidget);

    await tester.longPress(find.text('Heater plug'));
    await tester.pumpAndSettle();
    expect(find.text('Power now'), findsOneWidget);
    expect(find.text('12.3 W'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    adapter.set(
      'd1',
      const DeviceState(values: {Capability.onOff: false, Capability.power: 0}),
    );
    await tester.pumpAndSettle();
    expect(find.text('Off'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
