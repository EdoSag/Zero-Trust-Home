import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_home/adapters/homeassistant/ha_adapter.dart';
import 'package:zerotrust_home/adapters/homeassistant/ha_client.dart';
import 'package:zerotrust_home/adapters/homeassistant/ha_entities.dart';
import 'package:zerotrust_home/adapters/homeassistant/ha_server.dart';
import 'package:zerotrust_home/model/device.dart';

import '../support/fake_ha.dart';

const server = HaServer(
  homeId: 'h1',
  url: 'http://192.168.1.10:8123',
  token: 'good-token',
);

HomeDevice entityDevice(String entity, {String id = 'd1'}) {
  final adapter = HomeAssistantAdapter(loadServer: (_) async => server);
  final shape = HaEntity.from(haState(entity, 'off'))!;
  return adapter.deviceFor(id: id, homeId: 'h1', entity: shape);
}

/// A service call as a list, for deep comparison.
List<Object?>? asList((String, String, Map<String, dynamic>)? call) =>
    call == null ? null : [call.$1, call.$2, call.$3];

/// Lets queued messages through.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('addresses', () {
    test('what people type becomes a server address', () {
      expect(
        HaServer.normalizeUrl('homeassistant.local'),
        'http://homeassistant.local:8123',
      );
      expect(
        HaServer.normalizeUrl(' 192.168.1.10:8123 '),
        'http://192.168.1.10:8123',
      );
      expect(
        HaServer.normalizeUrl('https://ha.example.com'),
        'https://ha.example.com',
      );
      expect(
        HaServer.normalizeUrl('http://10.0.0.2:8123/'),
        'http://10.0.0.2:8123',
      );
      expect(HaServer.normalizeUrl(''), isNull);
      expect(HaServer.normalizeUrl('ftp://x'), isNull);
    });

    test('the API is reached over WebSocket at the same place', () {
      expect(
        server.socketUri.toString(),
        'ws://192.168.1.10:8123/api/websocket',
      );
      expect(
        const HaServer(
          homeId: 'h',
          url: 'https://ha.example.com/base',
          token: 't',
        ).socketUri.toString(),
        'wss://ha.example.com/base/api/websocket',
      );
    });

    test('the server item has one id per home', () {
      expect(HaServer.itemId('h1'), HaServer.itemId('h1'));
      expect(HaServer.itemId('h1'), isNot(HaServer.itemId('h2')));
      expect(HaServer.fromJson(server.toJson()).signature, server.signature);
    });
  });

  group('entities', () {
    test('each kind becomes a device with what it can do', () {
      HaEntity? e(String id, [Map<String, dynamic> a = const {}]) =>
          HaEntity.from(haState(id, 'on', a));
      final lamp = e('light.desk', {
        'friendly_name': 'Desk lamp',
        'supported_color_modes': ['color_temp', 'hs'],
      })!;
      expect(lamp.name, 'Desk lamp');
      expect(lamp.type, DeviceType.light);
      expect(lamp.capabilities, {
        Capability.onOff,
        Capability.brightness,
        Capability.colorTemperature,
        Capability.color,
      });
      expect(
        e('light.plain', {
          'supported_color_modes': ['onoff'],
        })!.capabilities,
        {Capability.onOff},
      );
      expect(e('switch.tv', {'device_class': 'outlet'})!.type, DeviceType.plug);
      expect(e('switch.relay')!.type, DeviceType.wallSwitch);
      expect(e('lock.front')!.capabilities, {Capability.locked});
      expect(e('cover.blind')!.capabilities, {Capability.position});
      expect(e('fan.ceiling', {'supported_features': 1})!.capabilities, {
        Capability.onOff,
        Capability.fanSpeed,
      });
      expect(e('binary_sensor.door', {'device_class': 'door'})!.capabilities, {
        Capability.contact,
      });
      expect(e('sensor.temp', {'device_class': 'temperature'})!.capabilities, {
        Capability.temperature,
      });
      // No use for these.
      expect(e('automation.lights'), isNull);
      expect(e('sensor.uptime'), isNull);
      expect(e('binary_sensor.update', {'device_class': 'update'}), isNull);
      expect(HaEntity.from(const {'state': 'on'}), isNull);
      // Without a friendly name, the id.
      expect(e('switch.relay')!.name, 'switch.relay');
    });

    test('states read as the app\'s values', () {
      final light = haRead(
        haState('light.desk', 'on', {
          'brightness': 128,
          'color_temp_kelvin': 2700,
          'rgb_color': [255, 128, 0],
        }),
      );
      expect(light.reachable, isTrue);
      expect(light.on, isTrue);
      expect(light.number(Capability.brightness), 50);
      expect(light.number(Capability.colorTemperature), 2700);
      expect(light.values[Capability.color], 0xff8000);

      expect(haRead(haState('light.desk', 'unavailable')).reachable, isFalse);
      expect(haRead(null).reachable, isFalse);
      expect(
        haRead(haState('lock.front', 'locked')).values[Capability.locked],
        isTrue,
      );
      // Jammed or moving: no answer either way.
      expect(
        haRead(haState('lock.front', 'jammed')).values,
        isNot(contains(Capability.locked)),
      );
      expect(
        haRead(haState('cover.blind', 'closed')).number(Capability.position),
        0,
      );
      expect(
        haRead(
          haState('cover.blind', 'open', {'current_position': 40}),
        ).number(Capability.position),
        40,
      );
      final thermostat = haRead(
        haState('climate.hall', 'heat', {
          'current_temperature': 68,
          'temperature': 72,
          'temperature_unit': '°F',
        }),
      );
      expect(thermostat.on, isTrue);
      expect(thermostat.number(Capability.temperature), 20);
      expect(thermostat.number(Capability.targetTemperature), 22.2);
      expect(
        haRead(
          haState('sensor.p', '1.5', {
            'device_class': 'power',
            'unit_of_measurement': 'kW',
          }),
        ).number(Capability.power),
        1500,
      );
      expect(
        haRead(
          haState('binary_sensor.hall', 'on', {'device_class': 'motion'}),
        ).values[Capability.motion],
        isTrue,
      );
      expect(
        haRead(
          haState('sensor.t', 'unknown', {'device_class': 'temperature'}),
        ).values,
        isEmpty,
      );
    });

    test('commands become service calls', () {
      expect(asList(haWrite('light.a', const DeviceCommand.turn(true), null)), [
        'light',
        'turn_on',
        <String, dynamic>{},
      ]);
      expect(
        haWrite(
          'light.a',
          const DeviceCommand(Capability.brightness, 30),
          null,
        )!.$3,
        {'brightness_pct': 30},
      );
      expect(
        haWrite(
          'light.a',
          const DeviceCommand(Capability.brightness, 0),
          null,
        )!.$2,
        'turn_off',
      );
      expect(
        haWrite(
          'light.a',
          const DeviceCommand(Capability.color, 0x00ff80),
          null,
        )!.$3,
        {
          'rgb_color': [0, 255, 128],
        },
      );
      expect(
        asList(
          haWrite(
            'lock.f',
            const DeviceCommand(Capability.locked, false),
            null,
          ),
        ),
        ['lock', 'unlock', <String, dynamic>{}],
      );
      // A blind that can only open and close.
      expect(
        haWrite(
          'cover.b',
          const DeviceCommand(Capability.position, 30),
          haState('cover.b', 'closed'),
        )!.$2,
        'open_cover',
      );
      expect(
        asList(
          haWrite(
            'cover.b',
            const DeviceCommand(Capability.position, 30),
            haState('cover.b', 'closed', {'supported_features': 15}),
          ),
        ),
        [
          'cover',
          'set_cover_position',
          {'position': 30},
        ],
      );
      expect(
        haWrite(
          'climate.h',
          const DeviceCommand(Capability.targetTemperature, 20),
          haState('climate.h', 'heat', {'temperature_unit': '°F'}),
        )!.$3,
        {'temperature': 68.0},
      );
      expect(haWrite('sensor.t', const DeviceCommand.turn(true), null), isNull);
    });
  });

  group('client', () {
    test('signs in, lists, follows changes and calls services', () async {
      final ha = FakeHa(states: [haState('switch.tv', 'off')]);
      final client = await HaClient.connect(
        ha.connect,
        server.socketUri,
        'good-token',
      );
      expect(ha.uris.single.toString(), 'ws://192.168.1.10:8123/api/websocket');
      expect((await client.states()).single['state'], 'off');
      final changes = await client.changes();
      final next = changes.first;
      ha.change('switch.tv', 'on');
      expect((await next).$2!['state'], 'on');
      await client.callService('switch', 'turn_off', 'switch.tv');
      expect(ha.calls.single.$2, 'turn_off');
      await expectLater(
        client.callService('switch', 'turn_on', 'switch.nope'),
        throwsA(
          isA<HaException>().having((e) => e.failure, 'f', HaFailure.failed),
        ),
      );
      await client.close();
      expect(ha.open, 0);
    });

    test('says why it could not connect', () async {
      final ha = FakeHa();
      Future<HaFailure> failure(String token) async {
        try {
          await HaClient.connect(ha.connect, server.socketUri, token);
        } on HaException catch (e) {
          return e.failure;
        }
        fail('connected');
      }

      expect(await failure('wrong'), HaFailure.badToken);
      ha.down = true;
      expect(await failure('good-token'), HaFailure.unreachable);
      ha
        ..down = false
        ..silent = true;
      final silent = HaClient.connect(ha.connect, server.socketUri, 'x');
      // Nothing ever greets: it isn't Home Assistant.
      ha.sockets.last.close().ignore();
      await expectLater(
        silent,
        throwsA(
          isA<HaException>().having(
            (e) => e.failure,
            'f',
            HaFailure.notHomeAssistant,
          ),
        ),
      );
    });
  });

  group('adapter', () {
    late FakeHa ha;
    late HomeAssistantAdapter adapter;
    HaServer? saved;

    setUp(() {
      ha = FakeHa(
        states: [
          haState('light.desk', 'off', {
            'friendly_name': 'Desk',
            'supported_color_modes': ['brightness'],
          }),
          haState('switch.tv', 'on', {'friendly_name': 'TV'}),
          haState('sun.sun', 'above_horizon'),
        ],
      );
      saved = server;
      adapter = HomeAssistantAdapter(
        loadServer: (_) async => saved,
        connect: ha.connect,
        linger: const Duration(milliseconds: 20),
        retryAfter: const [Duration(milliseconds: 10)],
      );
    });
    tearDown(() => adapter.dispose());

    test('lists what can be added, by name', () async {
      final entities = await adapter.entities(server);
      expect([for (final e in entities) e.name], ['Desk', 'TV']);
      expect(ha.open, 0);
    });

    test('one connection follows every entity of the home', () async {
      final desk = entityDevice('light.desk');
      final tv = entityDevice('switch.tv', id: 'd2');
      final deskStates = <DeviceState>[];
      final tvStates = <DeviceState>[];
      final a = adapter.watch(desk).listen(deskStates.add);
      final b = adapter.watch(tv).listen(tvStates.add);
      await settle();
      expect(ha.sockets, hasLength(1));
      expect(deskStates.last.on, isFalse);
      expect(tvStates.last.on, isTrue);

      ha.change('light.desk', 'on', {'brightness': 255});
      await settle();
      expect(deskStates.last.on, isTrue);
      expect(deskStates.last.number(Capability.brightness), 100);

      await adapter.send(desk, const DeviceCommand(Capability.brightness, 40));
      final call = ha.calls.single;
      expect(
        [call.$1, call.$2, call.$3, call.$4],
        [
          'light',
          'turn_on',
          'light.desk',
          {'brightness_pct': 40},
        ],
      );
      expect(ha.sockets, hasLength(1));

      await a.cancel();
      await b.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(ha.open, 0);
    });

    test('a restart shows devices unreachable, then back', () async {
      final states = <DeviceState>[];
      final sub = adapter.watch(entityDevice('switch.tv')).listen(states.add);
      await settle();
      expect(states.last.on, isTrue);

      ha.down = true;
      ha.restart();
      await settle();
      expect(states.last.reachable, isFalse);

      ha.down = false;
      ha.states['switch.tv'] = haState('switch.tv', 'off');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await settle();
      expect(states.last.reachable, isTrue);
      expect(states.last.on, isFalse);
      await sub.cancel();
    });

    test(
      'a home without Home Assistant shows its devices unreachable',
      () async {
        saved = null;
        final state = await adapter.watch(entityDevice('switch.tv')).first;
        expect(state.reachable, isFalse);
        await expectLater(
          adapter.send(
            entityDevice('switch.tv'),
            const DeviceCommand.turn(true),
          ),
          throwsA(isA<HaException>()),
        );
      },
    );

    test('a new token moves what is on screen to the new connection', () async {
      final states = <DeviceState>[];
      final sub = adapter.watch(entityDevice('switch.tv')).listen(states.add);
      await settle();
      ha.token = 'new-token';
      saved = const HaServer(
        homeId: 'h1',
        url: 'http://192.168.1.10:8123',
        token: 'new-token',
      );
      await adapter.send(
        entityDevice('switch.tv'),
        const DeviceCommand.turn(false),
      );
      expect(ha.calls.single.$2, 'turn_off');
      // The tile already on screen keeps following the device.
      ha.change('switch.tv', 'off');
      await settle();
      expect(states.last.reachable, isTrue);
      expect(states.last.on, isFalse);
      expect(ha.open, 1);
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(ha.open, 0);
    });

    test('a connection that signs in but fails to start is closed', () async {
      ha.failStates = true;
      final states = <DeviceState>[];
      final sub = adapter.watch(entityDevice('switch.tv')).listen(states.add);
      await Future<void>.delayed(const Duration(milliseconds: 35));
      await settle();
      expect(ha.sockets.length, greaterThan(1)); // It kept trying...
      expect(ha.open, 0); // ...without leaving any open.
      expect(states.last.reachable, isFalse);
      ha.failStates = false;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await settle();
      expect(states.last.on, isTrue);
      expect(ha.open, 1);
      await sub.cancel();
    });

    test(
      'a command while nothing is on screen opens and then closes',
      () async {
        await adapter.send(
          entityDevice('switch.tv'),
          const DeviceCommand.turn(false),
        );
        expect(ha.calls.single.$2, 'turn_off');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(ha.open, 0);
      },
    );
  });
}
