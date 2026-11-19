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
