import 'package:flutter_test/flutter_test.dart';
import 'package:zero_trust_core/zero_trust_core.dart';
import 'package:zerotrust_home/adapters/matter/matter_adapter.dart';
import 'package:zerotrust_home/adapters/matter/matter_bridge.dart';
import 'package:zerotrust_home/adapters/matter/matter_fabric.dart';
import 'package:zerotrust_home/model/device.dart';

import '../support/fake_matter_bridge.dart';

void main() {
  late FakeMatterBridge bridge;
  late Map<String, MatterFabric> fabrics;
  late InMemoryPreferencesStore preferences;
  var ids = 0;

  MatterAdapter adapterOn(FakeMatterBridge bridge) {
    final adapter = MatterAdapter(
      bridge: bridge,
      loadFabric: (homeId) async => fabrics[homeId],
      makeFabric: (homeId) async =>
          fabrics.putIfAbsent(homeId, () => MatterFabric.create(homeId)),
      preferences: preferences,
      linger: Duration.zero,
      retryAfter: const [1],
    );
    addTearDown(adapter.dispose);
    return adapter;
  }

  setUp(() {
    bridge = FakeMatterBridge();
    fabrics = {};
    preferences = InMemoryPreferencesStore();
    ids = 0;
  });

  Future<List<HomeDevice>> pair(
    MatterAdapter adapter, {
    String homeId = 'h1',
    String? code,
  }) => adapter.pair(
    homeId: homeId,
    roomId: 'r1',
    name: 'Lamp',
    code: code ?? bridge.code,
    newId: () => 'd${++ids}',
  );

  test('a plug joins the home\'s fabric and becomes a device', () async {
    final adapter = adapterOn(bridge);
    final devices = await pair(adapter);

    final fabric = fabrics['h1']!;
    expect(bridge.started, [fabric.fabricId]);
    expect(bridge.adminSubjects, [fabric.adminSubject]);
    expect(devices, hasLength(1));
    final device = devices.single;
    expect(device.name, 'Lamp');
    expect(device.roomId, 'r1');
    expect(device.adapter, 'matter');
    expect(device.type, DeviceType.plug);
    expect(device.capabilities, {Capability.onOff});
    // It was given a certificate under the id the app saved for it.
    final address = MatterAddress.parse(device.address)!;
    expect(address.endpoint, 1);
    expect(bridge.joined.keys, [address.nodeId]);
    expect(address.nodeId, matches(RegExp(r'^[0-9A-F]{16}$')));
  });

  test('a power strip gives one device per socket, a bulb dims', () async {
    bridge = FakeMatterBridge(
      parts: {
        1: FakePart(),
        2: FakePart(),
        3: FakePart(deviceType: 0x0101, dims: true),
      },
    );
    final devices = await pair(adapterOn(bridge));
    expect([for (final d in devices) d.name], ['Lamp 1', 'Lamp 2', 'Lamp 3']);
    expect([for (final d in devices) d.id], ['d1', 'd2', 'd3']);
    expect(devices[2].type, DeviceType.light);
    expect(devices[2].capabilities, {Capability.onOff, Capability.brightness});
    // All parts are the same node.
    expect({
      for (final d in devices) MatterAddress.parse(d.address)!.nodeId,
    }, hasLength(1));
  });

  test('a wrong code adds nothing', () async {
    final adapter = adapterOn(bridge);
    await expectLater(
      pair(adapter, code: '00000000000'),
      throwsA(
        isA<MatterException>().having(
          (e) => e.failure,
          'failure',
          MatterFailure.unreachable,
        ),
      ),
    );
    expect(bridge.joined, isEmpty);
    // The next try works.
    expect(await pair(adapter), hasLength(1));
  });

  test('a device that joined but can\'t be read is taken out again', () async {
    final adapter = adapterOn(bridge);
    bridge.unreadable = true;
    await expectLater(pair(adapter), throwsA(isA<MatterException>()));
    expect(bridge.joined, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('the phone stays the same node across restarts', () async {
    await pair(adapterOn(bridge));
    // The app starts again, with the same key in the phone's key store.
    final again = FakeMatterBridge()
      ..phone.publicKey.setAll(0, bridge.phone.publicKey);
    final device = (await pair(adapterOn(again))).single;
    expect(again.certificates.single, bridge.certificates.single);
    expect(device.homeId, 'h1');
    // A phone whose key was lost (restored from a backup) gets a new
    // certificate.
    final restored = FakeMatterBridge();
    await pair(adapterOn(restored));
    expect(restored.certificates.single, isNot(bridge.certificates.single));
  });

  test('watching shows the state, and commands change it', () async {
    bridge = FakeMatterBridge(parts: {1: FakePart(dims: true)});
    final adapter = adapterOn(bridge);
    final device = (await pair(adapter)).single;
    final nodeId = MatterAddress.parse(device.address)!.nodeId;

    final states = <DeviceState>[];
    final sub = adapter.watch(device).listen(states.add);
    await pumpEventQueue();
    expect(states.first.reachable, isFalse);
    expect(states.last.reachable, isTrue);
    expect(states.last.values[Capability.onOff], false);
    expect(states.last.values[Capability.brightness], 100);

    await adapter.send(device, const DeviceCommand(Capability.onOff, true));
    await pumpEventQueue();
    final (node, endpoint, cluster, command, fields) = bridge.invoked.last;
    expect((node, endpoint, cluster, command), (nodeId, 1, 0x0006, 1));
    expect(fields, isEmpty);
    expect(states.last.values[Capability.onOff], true);

    await adapter.send(device, const DeviceCommand(Capability.brightness, 50));
    await pumpEventQueue();
    expect(bridge.invoked.last.$3, 0x0008);
    expect(bridge.invoked.last.$4, 4);
    expect(bridge.invoked.last.$5, {0: 127, 1: 0, 2: 0, 3: 0});
    expect(states.last.values[Capability.brightness], 50);

    // The lowest brightness is still a level the device accepts.
    await adapter.send(device, const DeviceCommand(Capability.brightness, 0));
    expect((bridge.invoked.last.$5 as Map)[0], 1);

    bridge.reachable(nodeId, false);
    await pumpEventQueue();
    expect(states.last.reachable, isFalse);
    bridge.reachable(nodeId, true);
    await pumpEventQueue();
    expect(states.last.reachable, isTrue);

    await sub.cancel();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bridge.subscribers(nodeId), 0);
  });

  test('the parts of one node share one subscription', () async {
    bridge = FakeMatterBridge(parts: {1: FakePart(), 2: FakePart()});
    final adapter = adapterOn(bridge);
    final devices = await pair(adapter);
    final nodeId = MatterAddress.parse(devices[0].address)!.nodeId;
    final first = <DeviceState>[];
    final second = <DeviceState>[];
    final a = adapter.watch(devices[0]).listen(first.add);
    final b = adapter.watch(devices[1]).listen(second.add);
    await pumpEventQueue();
    expect(bridge.subscribers(nodeId), 1);

    await adapter.send(devices[1], const DeviceCommand(Capability.onOff, true));
    await pumpEventQueue();
    expect(first.last.values[Capability.onOff], false);
    expect(second.last.values[Capability.onOff], true);
    await a.cancel();
    await b.cancel();
  });

  test('a device that doesn\'t answer is tried again', () async {
    final adapter = adapterOn(bridge);
    final device = (await pair(adapter)).single;
    bridge.silent = true;
    final states = <DeviceState>[];
    final sub = adapter.watch(device).listen(states.add);
    await pumpEventQueue();
    expect(states.last.reachable, isFalse);
    await expectLater(
      adapter.send(device, const DeviceCommand(Capability.onOff, true)),
      throwsA(isA<MatterException>()),
    );
    bridge.silent = false;
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(states.last.reachable, isTrue);
    await sub.cancel();
  });

  test('a phone that can\'t run Matter shows devices as unreachable', () async {
    final adapter = adapterOn(bridge);
    final device = (await pair(adapter)).single;
    final other = adapterOn(
      FakeMatterBridge()..failure = MatterFailure.unsupported,
    );
    final states = <DeviceState>[];
    final sub = other.watch(device).listen(states.add);
    await pumpEventQueue();
    expect(states.last.reachable, isFalse);
    await sub.cancel();
  });

  test('each home has its own fabric; the one in use is served', () async {
    final adapter = adapterOn(bridge);
    final first = (await pair(adapter)).single;
    final firstNode = MatterAddress.parse(first.address)!.nodeId;
    final states = <DeviceState>[];
    final sub = adapter.watch(first).listen(states.add);
    await pumpEventQueue();
    expect(states.last.reachable, isTrue);

    // Adding to another home moves the library to that home's fabric.
    final second = (await pair(adapter, homeId: 'h2')).single;
    expect(second.homeId, 'h2');
    expect(bridge.started, [fabrics['h1']!.fabricId, fabrics['h2']!.fabricId]);
    expect(states.last.reachable, isFalse);

    // The device still being watched gets its home back.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    expect(bridge.started.last, fabrics['h1']!.fabricId);
    expect(states.last.reachable, isTrue);
    expect(bridge.subscribers(firstNode), 1);
    await sub.cancel();
  });

  test('deleting the last part tells the device to leave', () async {
    bridge = FakeMatterBridge(parts: {1: FakePart(), 2: FakePart()});
    final adapter = adapterOn(bridge);
    final devices = await pair(adapter);
    final nodeId = MatterAddress.parse(devices[0].address)!.nodeId;

    await adapter.forget(devices[0], others: [devices[1]]);
    expect(bridge.removed, isEmpty);
    await adapter.forget(devices[1], others: const []);
    expect(bridge.removed, [nodeId]);

    // A device that is unplugged is deleted all the same.
    final plug = (await pair(adapter)).first;
    bridge.silent = true;
    await adapter.forget(plug, others: const []);
  });

  test('a device saved by a newer version is not touched', () async {
    final adapter = adapterOn(bridge);
    const strange = HomeDevice(
      id: 'd1',
      homeId: 'h1',
      name: 'Lamp',
      type: DeviceType.light,
      adapter: 'matter',
      address: {'node': 7},
      capabilities: {Capability.onOff},
    );
    expect((await adapter.watch(strange).first).reachable, isFalse);
    await expectLater(
      adapter.send(strange, const DeviceCommand(Capability.onOff, true)),
      throwsStateError,
    );
    await adapter.forget(strange, others: const []);
    expect(bridge.started, isEmpty);
  });
}
