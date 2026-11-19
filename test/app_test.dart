import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_home/model/device.dart';
import 'package:zerotrust_home/model/home.dart';
import 'package:zerotrust_home/ui/add_device_page.dart';
import 'package:zerotrust_home/ui/home_page.dart';
import 'package:zerotrust_home/ui/homes_page.dart';

import 'support/app.dart';

void main() {
  testWidgets('first run: name the home, pick rooms, and see them', (
    tester,
  ) async {
    await tester.pumpWidget(app(const HomePage()));
    await tester.pumpAndSettle();
    expect(find.text('Set up your home'), findsOneWidget);
    await tester.tap(find.text('Set up my home'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Flat');
    // Living room, Kitchen and Bedroom are picked already; swap one.
    await tester.tap(find.text('Bedroom'));
    await tester.tap(find.text('Balcony'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create home'));
    await tester.pumpAndSettle();

    expect(repo.homes.single.name, 'Flat');
    final rooms = repo.rooms..sort((a, b) => a.order.compareTo(b.order));
    expect(
      [for (final r in rooms) r.name],
      ['Living room', 'Kitchen', 'Balcony'],
    );
    expect(rooms.last.kind, RoomKind.balcony);

    // Back on the home, under its name, rooms top to bottom in that order.
    expect(find.text('Flat'), findsOneWidget);
    final tops = [
      for (final name in ['Living room', 'Kitchen', 'Balcony'])
        tester.getTopLeft(find.text(name)).dy,
    ];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(tops.toSet(), hasLength(3));
    expect(find.text('No devices yet'), findsOneWidget);
  });

  testWidgets('an empty name becomes "My home"', (tester) async {
    await tester.pumpWidget(app(const HomePage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up my home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create home'));
    await tester.pumpAndSettle();
    expect(repo.homes.single.name, 'My home');
  });

  testWidgets('a tap turns a device on and off, under its own room', (
    tester,
  ) async {
    final adapter = FakeAdapter();
    await tester.pumpWidget(
      app(
        const HomePage(),
        homes: const [flat],
        rooms: const [living, kitchen],
        devices: [plug()],
        adapters: [adapter],
      ),
    );
    await tester.pumpAndSettle();

    // The tile sits between its room's heading and the next room's.
    final tile = tester.getRect(find.text('Heater plug'));
    expect(tile.top, greaterThan(tester.getRect(find.text('Living room')).top));
    expect(tile.bottom, lessThan(tester.getRect(find.text('Kitchen')).top));
    expect(find.text('1 device'), findsOneWidget);
    expect(find.text('No devices'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('No devices yet'), findsNothing);

    await tester.tap(find.text('Heater plug'));
    await tester.pumpAndSettle();
    expect(adapter.sent.single.$1, 'd1');
    expect(adapter.sent.single.$2.value, true);
    expect(find.text('On'), findsOneWidget);

    await tester.tap(find.text('Heater plug'));
    await tester.pumpAndSettle();
    expect(adapter.sent.last.$2.value, false);
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('a device that does not answer says so and is not toggled', (
    tester,
  ) async {
    final adapter = FakeAdapter()..set('d1', const DeviceState.unreachable());
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
    expect(find.text('Not responding'), findsOneWidget);
    await tester.tap(find.text('Heater plug'));
    await tester.pumpAndSettle();
    expect(adapter.sent, isEmpty);
    // The details open instead.
    expect(find.text('Remove device'), findsOneWidget);
  });

  testWidgets('a failed command shows a message and leaves the state', (
    tester,
  ) async {
    final adapter = FakeAdapter()..failing = true;
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
    await tester.tap(find.text('Heater plug'));
    await tester.pump();
    expect(find.text("Heater plug didn't respond. Try again."), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('a device this version cannot reach is shown, not hidden', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const HomePage(),
        homes: const [flat],
        rooms: const [living],
        devices: [plug(adapter: 'from-the-future')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Heater plug'), findsOneWidget);
    expect(find.text('Needs a newer ZT Home'), findsOneWidget);
  });

  testWidgets('favourites are listed first; details move and remove', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const HomePage(),
        homes: const [flat],
        rooms: const [living, kitchen],
        devices: [
          plug(),
          plug(id: 'd2', name: 'Kettle', roomId: 'r2', favourite: true),
        ],
        adapters: [FakeAdapter()],
      ),
    );
    await tester.pumpAndSettle();
    // Kettle: once under Favourites (above the first room), once in Kitchen.
    expect(find.text('Kettle'), findsNWidgets(2));
    expect(
      tester.getRect(find.text('Favourites')).top,
      lessThan(tester.getRect(find.text('Living room')).top),
    );
    expect(
      tester.getRect(find.text('Kettle').first).bottom,
      lessThan(tester.getRect(find.text('Living room')).top),
    );

    await tester.longPress(find.text('Heater plug'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kitchen').last);
    await tester.pumpAndSettle();
    expect(repo.devices.firstWhere((d) => d.id == 'd1').roomId, 'r2');

    await tester.tap(find.text('Remove device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove device').last);
    await tester.pumpAndSettle();
    expect([for (final d in repo.devices) d.id], ['d2']);
    expect(find.text('Heater plug'), findsNothing);
  });

  testWidgets('deleting a room keeps its devices, without a room', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const HomePage(),
        homes: const [flat],
        rooms: const [living, kitchen],
        devices: [plug()],
        adapters: [FakeAdapter()],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Living room'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect([for (final r in repo.rooms) r.id], ['r2']);
    expect(repo.devices.single.roomId, isNull);
    // Back on the home: the plug is under "Not in a room", below Kitchen.
    expect(find.text('Living room'), findsNothing);
    expect(
      tester.getRect(find.text('Heater plug')).top,
      greaterThan(tester.getRect(find.text('Not in a room')).top),
    );
    expect(
      tester.getRect(find.text('Not in a room')).top,
      greaterThan(tester.getRect(find.text('Kitchen')).top),
    );
  });

  testWidgets('adding a room puts it last', (tester) async {
    await tester.pumpWidget(
      app(
        const HomePage(),
        homes: const [flat],
        rooms: const [living, kitchen],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a room'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Office'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Study');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final made = repo.rooms.firstWhere((r) => r.name == 'Study');
    expect((made.kind, made.order, made.homeId), (RoomKind.office, 2, 'h1'));
    expect(
      tester.getRect(find.text('Study')).top,
      greaterThan(tester.getRect(find.text('Kitchen')).top),
    );
  });

  testWidgets('homes: switch, and delete one with its rooms and devices', (
    tester,
  ) async {
    final fake = FakeAdapter();
    final prefs = InMemoryPreferencesStore();
    await tester.pumpWidget(
      app(
        const HomePage(),
        preferences: prefs,
        homes: const [
          flat,
          Home(id: 'h2', name: 'Cabin', createdAt: 2),
        ],
        rooms: const [
          living,
          Room(id: 'r9', homeId: 'h2', name: 'Loft'),
        ],
        devices: [
          plug(),
          const HomeDevice(
            id: 'd9',
            homeId: 'h2',
            roomId: 'r9',
            name: 'Stove',
            adapter: 'fake',
          ),
          const HomeDevice(
            id: 'd8',
            homeId: 'h2',
            name: 'Kettle',
            adapter: 'fake',
          ),
        ],
        adapters: [fake],
      ),
    );
    await tester.pumpAndSettle();
    // The oldest home shows until one is picked.
    expect(find.text('Living room'), findsOneWidget);
    expect(find.text('Loft'), findsNothing);

    await tester.tap(find.text('Flat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cabin'));
    await tester.pumpAndSettle();
    expect(await prefs.read('home.selected'), 'h2');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Loft'), findsOneWidget);
    expect(find.text('Living room'), findsNothing);

    // Delete the Cabin: the Flat is back, untouched.
    await tester.tap(find.text('Cabin'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect([for (final h in repo.homes) h.id], ['h1']);
    expect([for (final r in repo.rooms) r.id], ['r1']);
    expect([for (final d in repo.devices) d.id], ['d1']);
    // Its devices were let go first, each told only of those still left.
    expect(fake.forgotten, unorderedEquals(['d8', 'd9']));
    expect(fake.forgottenOthers, [
      unorderedEquals(['d1', fake.forgotten.last]),
      ['d1'],
    ]);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Living room'), findsOneWidget);
  });

  testWidgets('deleting a home: an unplugged device holds up no other', (
    tester,
  ) async {
    final fake = FakeAdapter()..hanging.add('d1');
    await tester.pumpWidget(
      app(
        const HomesPage(),
        homes: const [flat],
        devices: [
          plug(),
          plug(id: 'd2', name: 'Lamp'),
        ],
        adapters: [fake],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    // The second one is tried while the home and its keys are still there.
    await tester.pump(const Duration(seconds: 11));
    expect(fake.forgotten, ['d1', 'd2']);
    await tester.pumpAndSettle();
    expect(repo.homes, isEmpty);
    expect(repo.devices, isEmpty);
  });

  testWidgets('add a device: ways without an adapter are "Coming soon"', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(const AddDevicePage(), adapters: [FakeAdapter(id: 'matter')]),
    );
    await tester.pumpAndSettle();
    ListTile row(String title) => tester.widget<ListTile>(
      find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
    );
    expect(row('Matter').enabled, isTrue);
    expect(row('Home Assistant').enabled, isFalse);
    expect(row('Tuya / Smart Life').enabled, isFalse);
    // Every way but Matter.
    expect(find.text('Coming soon'), findsNWidgets(5));
  });
}
