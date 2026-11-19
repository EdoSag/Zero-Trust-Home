import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_home/adapters/tuya/tuya_adapter.dart';
import 'package:zerotrust_home/adapters/tuya/tuya_codec.dart';
import 'package:zerotrust_home/adapters/tuya/tuya_discovery.dart';
import 'package:zerotrust_home/adapters/tuya/tuya_link.dart';
import 'package:zerotrust_home/model/device.dart';

import '../support/fake_tuya_device.dart';

Uint8List keyOf(String s) => Uint8List.fromList(ascii.encode(s));

Future<TuyaLink> openTo(
  FakeTuyaDevice device, {
  String key = '0123456789abcdef',
  TuyaVersion? version,
  Duration timeout = const Duration(milliseconds: 600),
}) => TuyaLink.open(
  host: device.host,
  port: device.port,
  deviceId: device.deviceId,
  localKey: keyOf(key),
  version: version ?? device.version,
  timeout: timeout,
);

/// An adapter whose links go to [device], whatever address is asked for.
TuyaAdapter adapterFor(
  FakeTuyaDevice device, {
  List<String>? hosts,
  Set<String> dead = const {},
  void Function(HomeDevice, String)? onMoved,
}) => TuyaAdapter(
  pollEvery: const Duration(milliseconds: 150),
  linger: const Duration(milliseconds: 50),
  onMoved: onMoved,
  open:
      ({
        required host,
        required deviceId,
        required localKey,
        required version,
      }) {
        hosts?.add(host);
        if (dead.contains(host)) {
          throw const TuyaException(TuyaFailure.unreachable);
        }
        return TuyaLink.open(
          host: device.host,
          port: device.port,
          deviceId: deviceId,
          localKey: localKey,
          version: version,
          timeout: const Duration(milliseconds: 600),
        );
      },
);

/// Waits for something that arrives over a real socket.
Future<void> eventually(bool Function() ok) async {
  final end = DateTime.now().add(const Duration(seconds: 5));
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('Timed out');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  for (final version in TuyaVersion.values) {
    group('protocol ${version.text}', () {
      late FakeTuyaDevice device;
      setUp(() async => device = await FakeTuyaDevice.start(version: version));
      tearDown(() => device.stop());

      test('reads the plug, switches it and hears it change', () async {
        final link = await openTo(device);
        addTearDown(link.close);
        expect((await link.query())['1'], false);

        final changes = <Map<String, dynamic>>[];
        link.changes.listen(changes.add);
        await link.set({'1': true});
        expect(device.dps['1'], true);
        await eventually(() => changes.isNotEmpty && changes.last['1'] == true);

        // Someone presses the button on the plug.
        device.push({'1': false});
        await eventually(() => changes.last['1'] == false);

        await link.heartbeat();
      });

      test('a wrong local key is told apart from no answer', () async {
        await expectLater(
          () async {
            final link = await openTo(device, key: 'ffffffffffffffff');
            addTearDown(link.close);
            await link.query();
          }(),
          throwsA(
            isA<TuyaException>().having(
              (e) => e.failure,
              'failure',
              TuyaFailure.keyRejected,
            ),
          ),
        );
      });

      test('the link ends when the plug goes away', () async {
        final link = await openTo(device);
        await link.query();
        await device.drop();
        await link.done.timeout(const Duration(seconds: 2));
        expect(link.isOpen, isFalse);
        await expectLater(link.query(), throwsA(isA<TuyaException>()));
      });
    });
  }

  test('nothing at that address is "unreachable"', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    await expectLater(
      TuyaLink.open(
        host: '127.0.0.1',
        port: port,
        deviceId: 'x',
        localKey: keyOf('0123456789abcdef'),
        version: TuyaVersion.v33,
      ),
      throwsA(
        isA<TuyaException>().having(
          (e) => e.failure,
          'failure',
          TuyaFailure.unreachable,
        ),
      ),
    );
  });

  test('a device that wants its query as a control command gets it', () async {
    final device = await FakeTuyaDevice.start(version: TuyaVersion.v33)
      ..wantsQueryAsControl = true;
    addTearDown(device.stop);
    final link = await openTo(device);
    addTearDown(link.close);
    expect((await link.query())['1'], false);
    expect(device.received, [TuyaCommand.query, TuyaCommand.controlNew]);
  });

  group('device profile', () {
    test('a plug with power metering', () {
      final p = tuyaProfile({
        '1': true,
        '9': 0,
        '18': 52,
        '19': 123,
        '20': 2301,
      });
      expect(p.type, DeviceType.plug);
      expect(p.onOff, '1');
      expect(p.power, '19');
    });

    test('an older metering plug uses data point 5', () {
      final p = tuyaProfile({'1': true, '4': 52, '5': 123, '6': 2301});
      expect(p.power, '5');
    });

    test('a plain plug', () {
      final p = tuyaProfile({'1': false, '9': 0});
      expect((p.type, p.onOff, p.power), (DeviceType.plug, '1', null));
    });

    test('a light', () {
      final p = tuyaProfile({'20': true, '21': 'white', '22': 505});
      expect((p.type, p.onOff, p.brightness), (DeviceType.light, '20', '22'));
    });

    test('something unknown is added without controls', () {
      final p = tuyaProfile({'101': 'abc'});
      expect((p.type, p.onOff), (DeviceType.other, null));
    });
  });

  group('adapter', () {
    late FakeTuyaDevice device;
    setUp(
      () async => device = await FakeTuyaDevice.start(
        version: TuyaVersion.v34,
        dps: {'1': true, '19': 123},
      ),
    );
    tearDown(() => device.stop());

    Future<HomeDevice> pair(
      TuyaAdapter adapter, {
      String key = '0123456789abcdef',
    }) => adapter.pair(
      id: 'd1',
      homeId: 'h1',
      roomId: 'r1',
      name: 'Kettle',
      deviceId: device.deviceId,
      ip: '192.168.1.50',
      version: device.version,
      localKey: key,
    );

    test('pairing reads what the plug can do', () async {
      final adapter = adapterFor(device);
      addTearDown(adapter.dispose);
      final saved = await pair(adapter);
      expect(saved.adapter, 'tuya');
      expect(saved.type, DeviceType.plug);
      expect(saved.capabilities, {Capability.onOff, Capability.power});
      expect(saved.roomId, 'r1');
      final address = TuyaAddress.parse(saved.address)!;
      expect(address.ip, '192.168.1.50');
      expect(address.localKey, '0123456789abcdef');
      expect(address.version, TuyaVersion.v34);
      // Survives being saved and read back.
      final again = HomeDevice.fromJson('d1', saved.toJson());
      expect(TuyaAddress.parse(again.address)!.powerDp, '19');
    });

    test('pairing with a wrong key says so', () async {
      final adapter = adapterFor(device);
      addTearDown(adapter.dispose);
      await expectLater(
        pair(adapter, key: 'ffffffffffffffff'),
        throwsA(
          isA<TuyaException>().having(
            (e) => e.failure,
            'failure',
            TuyaFailure.keyRejected,
          ),
        ),
      );
      await expectLater(
        pair(adapter, key: 'too short'),
        throwsA(isA<TuyaException>()),
      );
    });

    test('shows state and power, switches, and reconnects', () async {
      final adapter = adapterFor(device);
      addTearDown(adapter.dispose);
      final saved = await pair(adapter);

      final states = <DeviceState>[];
      final sub = adapter.watch(saved).listen(states.add);
      addTearDown(sub.cancel);
      const until = eventually;

      await until(() => states.isNotEmpty);
      expect(states.first.reachable, isFalse);
      await until(() => states.last.reachable);
      expect(states.last.on, true);
      expect(states.last.number(Capability.power), 12.3);

      await adapter.send(saved, const DeviceCommand.turn(false));
      await until(() => states.last.on == false);
      expect(device.dps['1'], false);

      // The app keeps the connection alive and asks for fresh power.
      await until(
        () =>
            device.received.contains(TuyaCommand.heartbeat) &&
            device.received.contains(TuyaCommand.refresh),
      );

      // Pulled from the wall, then back.
      await device.drop();
      await until(() => !states.last.reachable);
      device.dps['1'] = true;
      await until(() => states.last.reachable && states.last.on == true);
    });

    test('a command reaches a device nobody is watching', () async {
      final adapter = adapterFor(device);
      addTearDown(adapter.dispose);
      final saved = await pair(adapter);
      await adapter.send(saved, const DeviceCommand.turn(false));
      expect(device.dps['1'], false);
      await expectLater(
        adapter.send(saved, const DeviceCommand(Capability.locked, true)),
        throwsStateError,
      );
    });

    test('follows a plug to the address it announces', () async {
      final hosts = <String>[];
      final moved = <String>[];
      final adapter = adapterFor(
        device,
        hosts: hosts,
        onMoved: (_, ip) => moved.add(ip),
      );
      addTearDown(adapter.dispose);
      final saved = await pair(adapter);
      hosts.clear();
      // The plug announces itself at a new address.
      adapter.discovery.handle(
        tuyaPack6699(
          sequence: 0,
          command: 19,
          returnCode: 0,
          payload: utf8.encode(
            jsonEncode({
              'ip': '192.168.1.77',
              'gwId': device.deviceId,
              'version': '3.4',
            }),
          ),
          key: tuyaBroadcastKey,
        ),
      );
      final states = <DeviceState>[];
      final sub = adapter.watch(saved).listen(states.add);
      addTearDown(sub.cancel);
      final end = DateTime.now().add(const Duration(seconds: 5));
      while (states.isEmpty || !states.last.reachable) {
        if (DateTime.now().isAfter(end)) fail('Never connected');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(hosts, ['192.168.1.77']);
      expect(moved, ['192.168.1.77']);
    });

    group('an address heard earlier that no longer answers', () {
      Uint8List announce(String ip) => tuyaPack6699(
        sequence: 0,
        command: 19,
        returnCode: 0,
        payload: utf8.encode(
          jsonEncode({'ip': ip, 'gwId': device.deviceId, 'version': '3.4'}),
        ),
        key: tuyaBroadcastKey,
      );

      test('watching goes back to the saved address', () async {
        final hosts = <String>[];
        final moved = <String>[];
        final adapter = adapterFor(
          device,
          hosts: hosts,
          dead: {'192.168.1.77'},
          onMoved: (_, ip) => moved.add(ip),
        );
        addTearDown(adapter.dispose);
        final saved = await pair(adapter);
        hosts.clear();
        adapter.discovery.handle(announce('192.168.1.77'));
        final states = <DeviceState>[];
        final sub = adapter.watch(saved).listen(states.add);
        addTearDown(sub.cancel);
        await eventually(() => states.isNotEmpty && states.last.reachable);
        expect(hosts, ['192.168.1.77', '192.168.1.50']);
        expect(moved, isEmpty);
        expect(adapter.discovery.found, isEmpty);
      });

      test('a command goes to the saved address too', () async {
        final hosts = <String>[];
        final adapter = adapterFor(
          device,
          hosts: hosts,
          dead: {'192.168.1.77'},
        );
        addTearDown(adapter.dispose);
        final saved = await pair(adapter);
        hosts.clear();
        adapter.discovery.handle(announce('192.168.1.77'));
        await adapter.send(saved, const DeviceCommand.turn(false));
        expect(device.dps['1'], false);
        expect(hosts, ['192.168.1.77', '192.168.1.50']);
      });
    });
  });

  test('discovery reports each device once, and again when it moves', () async {
    final discovery = TuyaDiscovery();
    Uint8List announce(String ip) => tuyaPack6699(
      sequence: 0,
      command: 19,
      returnCode: 0,
      payload: utf8.encode(
        jsonEncode({'ip': ip, 'gwId': 'dev1', 'version': '3.5'}),
      ),
      key: tuyaBroadcastKey,
    );
    discovery
      ..handle(announce('10.0.0.5'))
      ..handle(announce('10.0.0.5'))
      ..handle([1, 2, 3]);
    expect(discovery.found.keys, ['dev1']);
    expect(discovery.found['dev1']!.ip, '10.0.0.5');
    discovery.handle(announce('10.0.0.9'));
    expect(discovery.found['dev1']!.ip, '10.0.0.9');
  });
}
