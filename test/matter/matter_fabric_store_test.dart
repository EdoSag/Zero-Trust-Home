import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_home/adapters/matter/matter_fabric.dart';
import 'package:zerotrust_home/data/home_store.dart';
import 'package:zerotrust_home/model/home.dart';

import '../support/app.dart';

void main() {
  late MemoryRepository repo;
  setUp(() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    repo = container.read(Provider((ref) => MemoryRepository(ref)));
  });

  test('a home gets its fabric once, and keeps it', () async {
    expect(await repo.loadFabric('h1'), isNull);
    final first = await repo.fabricFor('h1');
    expect(first.homeId, 'h1');
    expect(first.isUsable, isTrue);
    final again = await repo.fabricFor('h1');
    expect(again.caKey, first.caKey);
    expect(again.fabricId, first.fabricId);
    // Another home has other keys.
    final other = await repo.fabricFor('h2');
    expect(other.caKey, isNot(first.caKey));
  });

  test('two calls at once make one fabric', () async {
    final both = await Future.wait([
      repo.fabricFor('h1'),
      repo.fabricFor('h1'),
    ]);
    expect(both[0].caKey, both[1].caKey);
    expect((await repo.loadFabric('h1'))!.caKey, both[0].caKey);
  });

  test('the fabric another phone made is used, not a second one', () async {
    final theirs = MatterFabric.create('h1');
    // It arrives with the sync that comes before making one.
    repo.onSync = () async => repo.fabrics['h1'] = theirs;
    final ours = await repo.fabricFor('h1');
    expect(ours.caKey, theirs.caKey);
  });

  test('one made in the same moment elsewhere wins everywhere', () async {
    final theirs = MatterFabric.create('h1');
    // Nothing on the first sync; theirs replaces ours on the second.
    repo.onSync = () async {
      if (repo.syncs == 2) repo.fabrics['h1'] = theirs;
    };
    final ours = await repo.fabricFor('h1');
    expect(ours.caKey, theirs.caKey);
  });

  test('one that arrives a moment after ours was sent still wins', () async {
    final theirs = MatterFabric.create('h1');
    // The other phone's write lands after ours was sent and confirmed.
    repo.onSync = () async {
      if (repo.syncs == 3) repo.fabrics['h1'] = theirs;
    };
    final ours = await repo.fabricFor('h1');
    expect(ours.caKey, theirs.caKey);
  });

  test('the account is asked again before each device is added', () async {
    final first = await repo.fabricFor('h1');
    // The account's copy was replaced since (a write that arrived late).
    final theirs = MatterFabric.create('h1');
    repo.onSync = () async => repo.fabrics['h1'] = theirs;
    final now = await repo.fabricFor('h1');
    expect(now.caKey, theirs.caKey);
    expect(now.caKey, isNot(first.caKey));
  });

  test('without a connection no fabric is made', () async {
    repo.onSync = () async => throw const MatterFabricNeedsSync();
    await expectLater(
      repo.fabricFor('h1'),
      throwsA(isA<MatterFabricNeedsSync>()),
    );
    expect(await repo.loadFabric('h1'), isNull);
    // Back online, it works; a saved fabric then needs no connection.
    repo.onSync = null;
    final fabric = await repo.fabricFor('h1');
    repo.onSync = () async => throw const MatterFabricNeedsSync();
    expect((await repo.fabricFor('h1')).caKey, fabric.caKey);
  });

  test('a fabric this version can\'t read is never replaced', () async {
    final unreadable = MatterFabric(
      homeId: 'h1',
      fabricId: '',
      caKey: '',
      rootCert: Uint8List(0),
      ipk: Uint8List(0),
      adminCat: '',
    );
    await repo.saveFabric(unreadable);
    await expectLater(
      repo.fabricFor('h1'),
      throwsA(isA<MatterFabricUnreadable>()),
    );
    expect(await repo.loadFabric('h1'), same(unreadable));
  });

  test('deleting a home deletes its keys', () async {
    await repo.saveHome(const Home(id: 'h1', name: 'Flat', createdAt: 1));
    await repo.fabricFor('h1');
    await repo.fabricFor('h2');
    await repo.deleteHome('h1');
    expect(await repo.loadFabric('h1'), isNull);
    expect(await repo.loadFabric('h2'), isNotNull);
  });

  test('the saved item says what it is', () {
    final fabric = MatterFabric.create('h1');
    final json = fabricsCollection.encode(fabric);
    expect(json['kind'], 'fabric');
    expect(fabricsCollection.idOf(fabric), MatterFabric.itemId('h1'));
    expect(fabricsCollection.owns(json), isTrue);
    expect(devicesCollection.owns(json), isFalse);
  });
}
