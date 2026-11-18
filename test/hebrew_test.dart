import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_home/ui/add_device_page.dart';
import 'package:zerotrust_home/ui/home_page.dart';

import 'support/app.dart';

void main() {
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('Hebrew: right to left, translated, nothing overflows', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(
      app(
        const HomePage(),
        locale: ZtLanguages.hebrew,
        homes: const [flat],
        rooms: const [living, kitchen],
        devices: [
          plug(name: 'שקע של תנור החימום בסלון'),
          plug(id: 'd2', name: 'מנורה'),
        ],
        adapters: [FakeAdapter()],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      Directionality.of(tester.element(find.byType(HomePage))),
      TextDirection.rtl,
    );
    expect(find.text('2 מכשירים'), findsOneWidget);
    expect(find.text('אין מכשירים'), findsOneWidget);
    expect(find.text('כבוי'), findsNWidgets(2));
    // The room's icon is to the right of its name, the count to the left.
    final name = tester.getRect(find.text('Living room'));
    expect(
      tester.getRect(find.byIcon(Icons.weekend_outlined)).left,
      greaterThan(name.right - 1),
    );
    expect(
      tester.getRect(find.text('2 מכשירים')).right,
      lessThanOrEqualTo(name.left),
    );
    // Two tiles side by side, the first on the right.
    final first = tester.getRect(find.text('מנורה'));
    final second = tester.getRect(find.text('שקע של תנור החימום בסלון'));
    expect(first.left, greaterThan(second.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hebrew: setting up a home and adding a device fit', (
    tester,
  ) async {
    phone(tester);
    await tester.pumpWidget(app(const HomePage(), locale: ZtLanguages.hebrew));
    await tester.pumpAndSettle();
    await tester.tap(find.text('להגדרת הבית'));
    await tester.pumpAndSettle();
    expect(find.text('אילו חדרים יש בו?'), findsOneWidget);
    await tester.tap(find.text('יצירת הבית'));
    await tester.pumpAndSettle();
    expect(repo.homes.single.name, 'הבית שלי');
    expect(
      [for (final r in repo.rooms) r.name]..sort(),
      ['חדר שינה', 'מטבח', 'סלון']..sort(),
    );
    expect(tester.takeException(), isNull);

    // From the home: Add, then a device.
    await tester.tap(find.text('הוספה'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('הוספת מכשיר').last);
    await tester.pumpAndSettle();
    expect(find.byType(AddDevicePage), findsOneWidget);
    expect(find.text('בקרוב'), findsAtLeastNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}
