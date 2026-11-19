import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_home/adapters/matter/matter_adapter.dart';
import 'package:zerotrust_home/adapters/matter/matter_bridge.dart';
import 'package:zerotrust_home/adapters/matter/matter_providers.dart';
import 'package:zerotrust_home/ui/add_device_page.dart';
import 'package:zerotrust_home/ui/matter_add_page.dart';

import '../support/app.dart';
import '../support/fake_matter_bridge.dart';

late FakeMatterBridge bridge;

Widget matterApp(Widget home, {Locale locale = ZtLanguages.english}) {
  bridge = FakeMatterBridge();
  return app(
    home,
    homes: const [flat],
    rooms: const [living, kitchen],
    adapters: [FakeAdapter(id: 'matter')],
    locale: locale,
    overrides: [matterBridgeProvider.overrideWithValue(bridge)],
  );
}

void phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<void> typeCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byType(TextFormField).first, code);
  await tester.scrollUntilVisible(
    find.byType(FilledButton),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.byType(FilledButton));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Matter is a way to add a device', (tester) async {
    phone(tester);
    await tester.pumpWidget(matterApp(const AddDevicePage()));
    await tester.pumpAndSettle();
    final row = tester.widget<ListTile>(
      find.ancestor(of: find.text('Matter'), matching: find.byType(ListTile)),
    );
    expect(row.enabled, isTrue);
    await tester.tap(find.text('Matter'));
    await tester.pumpAndSettle();
    expect(find.byType(MatterAddPage), findsOneWidget);
    expect(find.text('Setup code'), findsOneWidget);
    // The code comes first, above the name.
    expect(
      tester.getTopLeft(find.text('Setup code')).dy,
      lessThan(tester.getTopLeft(find.text('Name')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a mistyped code is caught before anything is tried', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(matterApp(const MatterAddPage()));
    await tester.pumpAndSettle();
    await typeCode(tester, '34970112333');
    expect(
      find.text(
        'One of the digits is wrong. Check the code and type it again.',
      ),
      findsOneWidget,
    );
    await typeCode(tester, 'hello');
    expect(
      find.textContaining("This isn't a Matter setup code"),
      findsOneWidget,
    );
    expect(bridge.started, isEmpty);
  });

  testWidgets('a good code adds the device to the home', (tester) async {
    phone(tester);
    await tester.pumpWidget(matterApp(const MatterAddPage()));
    await tester.pumpAndSettle();
    // Typed the way it is printed, with dashes.
    await typeCode(tester, '3497-011-2332');
    final device = repo.devices.single;
    expect(device.name, 'Matter device');
    expect(device.adapter, MatterAdapter.adapterId);
    expect(device.homeId, flat.id);
    expect(bridge.joined, hasLength(1));
    expect(find.text('Matter device added'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a device that isn\'t found says what to check', (tester) async {
    phone(tester);
    await tester.pumpWidget(matterApp(const MatterAddPage()));
    await tester.pumpAndSettle();
    // A valid code, but no device answers to it.
    await typeCode(tester, 'MT:Y.K9042C00KA0648G00');
    expect(find.textContaining("The device wasn't found"), findsOneWidget);
    expect(repo.devices, isEmpty);

    bridge.failure = MatterFailure.unsupported;
    await typeCode(tester, '34970112332');
    expect(find.textContaining("This phone can't run Matter"), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the page is in Hebrew too, with the code left to right', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      matterApp(const MatterAddPage(), locale: ZtLanguages.hebrew),
    );
    await tester.pumpAndSettle();
    expect(find.text('הוספת מכשיר Matter'), findsOneWidget);
    expect(find.text('קוד הגדרה'), findsOneWidget);
    final field = tester.widget<EditableText>(find.byType(EditableText).first);
    expect(field.textDirection, TextDirection.ltr);
    expect(tester.takeException(), isNull);
  });
}
