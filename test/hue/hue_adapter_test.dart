import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_home/adapters/hue/hue_adapter.dart';
import 'package:zerotrust_home/adapters/hue/hue_bridge.dart';
import 'package:zerotrust_home/adapters/hue/hue_lights.dart';
import 'package:zerotrust_home/adapters/hue/hue_link.dart';
import 'package:zerotrust_home/model/device.dart';

import '../support/fake_hue.dart';

const bridge = HueBridge(
  homeId: 'h1',
  host: '192.168.1.20',
  key: FakeHue.key,
  certificate: FakeHue.certificate,
);

/// Lets queued messages through.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

late FakeHue hue;
HueBridge? saved;

HueAdapter adapter() => HueAdapter(
  loadBridge: (_) async => saved,
  connect: hue.connect,
  linger: const Duration(milliseconds: 20),
  retryAfter: const [Duration(milliseconds: 20)],
);

HomeDevice device(HueAdapter a, String light) => a.deviceFor(
  id: 'd-$light',
  homeId: 'h1',
  light: HueLight.from(hue.lights[light]!)!,
);

void main() {
  setUp(() {
    saved = bridge;
    hue = FakeHue(
      lights: [
        hueLight('desk', 'Desk lamp', brightness: 40, mirek: 250),
        hueLight(
          'strip',
          'TV strip',
          on: true,
          brightness: 80,
          xy: (0.64, 0.33),
        ),
        hueLight('plug', 'Heater', archetype: 'plug'),
      ],
    );
  });

  test('what people type becomes a bridge address', () {
    expect(HueBridge.normalizeHost(' 192.168.1.20 '), '192.168.1.20');
    expect(HueBridge.normalizeHost('https://192.168.1.20/'), '192.168.1.20');
    expect(HueBridge.normalizeHost('hue.local:8443'), 'hue.local:8443');
    expect(HueBridge.normalizeHost(''), isNull);
    expect(HueBridge.normalizeHost('not an address'), isNull);
  });

  test('a bridge is saved and read back whole', () {
    final back = HueBridge.fromJson(bridge.toJson());
    expect(back.signature, bridge.signature);
    expect(back.id, HueBridge.itemId('h1'));
  });

  test('colours survive the trip to Hue and back', () {
    for (final rgb in [0xFF0000, 0x00FF00, 0x0000FF, 0xFFFFFF, 0xFFAA33]) {
      final (x, y) = hueRgbToXy(rgb);
      final back = hueXyToRgb(x, y);
      for (final shift in [16, 8, 0]) {
        expect(
          ((back >> shift) & 0xFF) - ((rgb >> shift) & 0xFF),
          inInclusiveRange(-3, 3),
          reason: rgb.toRadixString(16),
        );
      }
    }
    final (x, y) = hueRgbToXy(0xFF0000);
    expect(x, closeTo(0.64, 0.001));
    expect(y, closeTo(0.33, 0.001));
  });

  test('the bridge\'s event lines become changes', () {
    expect(
      hueEventChanges(
        '[{"type":"update","data":[{"id":"desk","type":"light","on":{"on":true}}]},'
        '{"type":"delete","data":[{"id":"x","type":"light"}]}]',
      ),
      [
        {
          'id': 'desk',
          'type': 'light',
          'on': {'on': true},
        },
      ],
    );
    expect(hueEventChanges(' hi'), isEmpty);
  });

  group('pairing', () {
    test('needs the button, then gives a key and the certificate', () async {
      final a = adapter();
      await expectLater(
        a.pair(homeId: 'h1', host: '192.168.1.20'),
        throwsA(
          isA<HueException>().having(
            (e) => e.failure,
            'failure',
            HueFailure.pressButton,
          ),
        ),
      );
      hue.pressed = true;
      final paired = await a.pair(homeId: 'h1', host: '192.168.1.20');
      expect(paired.key, FakeHue.key);
      expect(paired.certificate, FakeHue.certificate);
      expect(paired.host, '192.168.1.20');
      // Nothing left open.
      expect(hue.links.every((l) => l.closed), isTrue);
    });

    test('says when nothing or something else answers', () async {
      final a = adapter();
      hue.down = true;
      await expectLater(
        a.pair(homeId: 'h1', host: '192.168.1.20'),
        throwsA(
          isA<HueException>().having(
            (e) => e.failure,
            'failure',
            HueFailure.unreachable,
          ),
        ),
      );
      hue
        ..down = false
        ..stranger = true;
      await expectLater(
        a.pair(homeId: 'h1', host: '192.168.1.20'),
        throwsA(
          isA<HueException>().having(
            (e) => e.failure,
            'failure',
            HueFailure.notHue,
          ),
        ),
      );
    });
  });

  test('lists lights and plugs with what each can do', () async {
    final lights = await adapter().lights(bridge);
    expect(lights.map((l) => l.name), ['Desk lamp', 'Heater', 'TV strip']);
    final byId = {for (final l in lights) l.id: l};
    expect(byId['desk']!.capabilities, {
      Capability.onOff,
      Capability.brightness,
      Capability.colorTemperature,
    });
    expect(byId['strip']!.capabilities, contains(Capability.color));
    expect(byId['plug']!.type, DeviceType.plug);
    expect(byId['plug']!.capabilities, {Capability.onOff});
  });

  test('a bridge with another certificate is never talked to', () async {
    hue.shown = 'bb22';
    await expectLater(
      adapter().lights(bridge),
      throwsA(
        isA<HueException>().having(
          (e) => e.failure,
          'failure',
          HueFailure.changed,
        ),
      ),
    );
    final a = adapter();
    final states = <DeviceState>[];
    final sub = a.watch(device(a, 'desk')).listen(states.add);
    await settle();
    expect(states.last.reachable, isFalse);
    await expectLater(
      a.send(device(a, 'desk'), const DeviceCommand.turn(true)),
      throwsA(isA<HueException>()),
    );
    expect(hue.puts, isEmpty);
    await sub.cancel();
    await a.dispose();
  });

  group('watching and switching', () {
    test('shows the state now and as it changes', () async {
      final a = adapter();
      final states = <DeviceState>[];
      final sub = a.watch(device(a, 'desk')).listen(states.add);
      await settle();
      expect(states.last.reachable, isTrue);
      expect(states.last.on, isFalse);
      expect(states.last.number(Capability.brightness), 40);
      expect(states.last.number(Capability.colorTemperature), 4000);

      hue.change('desk', {
        'on': {'on': true},
      });
      await settle();
      expect(states.last.on, isTrue);
      // What didn't change is kept.
      expect(states.last.number(Capability.brightness), 40);

      hue.reach('desk', connected: false);
      await settle();
      expect(states.last.reachable, isFalse);
      hue.reach('desk', connected: true);
      await settle();
      expect(states.last.reachable, isTrue);
      await sub.cancel();
      await a.dispose();
    });

    test('sends what Hue understands', () async {
      final a = adapter();
      final desk = device(a, 'desk');
      final strip = device(a, 'strip');
      await a.send(desk, const DeviceCommand.turn(true));
      await a.send(desk, const DeviceCommand(Capability.brightness, 55));
      await a.send(desk, const DeviceCommand(Capability.brightness, 0));
      await a.send(
        desk,
        const DeviceCommand(Capability.colorTemperature, 2700),
      );
      await a.send(strip, const DeviceCommand(Capability.color, 0xFF0000));
      expect(hue.puts.map((p) => (p.$1, p.$2.toString())).toList(), [
        ('desk', '{on: {on: true}}'),
        ('desk', '{on: {on: true}, dimming: {brightness: 55}}'),
        ('desk', '{on: {on: false}}'),
        ('desk', '{color_temperature: {mirek: 370}}'),
        ('strip', '{color: {xy: {x: 0.6401, y: 0.33}}}'),
      ]);
      await expectLater(
        a.send(desk, const DeviceCommand(Capability.locked, true)),
        throwsStateError,
      );
      await a.dispose();
    });

    test('a light the bridge no longer has is refused, not ignored', () async {
      final a = adapter();
      final desk = device(a, 'desk');
      hue.lights.remove('desk');
      await expectLater(
        a.send(desk, const DeviceCommand.turn(true)),
        throwsA(isA<HueException>()),
      );
      await a.dispose();
    });

    test('comes back by itself after the bridge restarts', () async {
      final a = adapter();
      final states = <DeviceState>[];
      final sub = a.watch(device(a, 'desk')).listen(states.add);
      await settle();
      expect(states.last.reachable, isTrue);
      hue.restart();
      await settle();
      expect(states.last.reachable, isFalse);
      hue.lights['desk'] = hueLight('desk', 'Desk lamp', on: true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await settle();
      expect(states.last.reachable, isTrue);
      expect(states.last.on, isTrue);
      await sub.cancel();
      await a.dispose();
    });

    test('stops listening once nothing is on screen', () async {
      final a = adapter();
      final sub = a.watch(device(a, 'desk')).listen((_) {});
      await settle();
      expect(hue.listening, 1);
      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 60));
      hue.change('desk', {
        'on': {'on': true},
      });
      // Watching again reads the bridge afresh.
      final states = <DeviceState>[];
      final again = a.watch(device(a, 'desk')).listen(states.add);
      await settle();
      expect(states.last.on, isTrue);
      await again.cancel();
      await a.dispose();
    });

    test('no bridge saved: not reachable, and says so on a command', () async {
      saved = null;
      final a = adapter();
      final desk = device(a, 'desk');
      expect((await a.watch(desk).first).reachable, isFalse);
      await expectLater(
        a.send(desk, const DeviceCommand.turn(true)),
        throwsA(isA<HueException>()),
      );
    });
  });
}
