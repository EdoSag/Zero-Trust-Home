import 'dart:async';

import 'package:zerotrust_home/adapters/hue/hue_link.dart';

Map<String, dynamic> hueLight(
  String id,
  String name, {
  bool on = false,
  num? brightness,
  num? mirek,
  (double, double)? xy,
  String archetype = 'sultan_bulb',
}) => {
  'id': id,
  'type': 'light',
  'owner': {'rid': 'dev-$id', 'rtype': 'device'},
  'metadata': {'name': name, 'archetype': archetype},
  'on': {'on': on},
  if (brightness != null) 'dimming': {'brightness': brightness},
  if (mirek != null) 'color_temperature': {'mirek': mirek},
  if (xy != null)
    'color': {
      'xy': {'x': xy.$1, 'y': xy.$2},
    },
};

/// A Hue Bridge that lives in memory and speaks its local API.
class FakeHue {
  FakeHue({List<Map<String, dynamic>> lights = const []}) {
    for (final l in lights) {
      this.lights[l['id'] as String] = l;
    }
  }

  static const key = 'good-key';
  static const certificate = 'aa11';

  final lights = <String, Map<String, dynamic>>{};

  /// Device ids the bridge can't reach over Zigbee.
  final lost = <String>{};

  /// (light id, body) of each change asked for.
  final puts = <(String, Map<String, dynamic>)>[];
  final hosts = <String>[];
  final links = <FakeHueLink>[];

  /// The round button was pressed just now.
  bool pressed = false;

  /// Nothing listens at the address.
  bool down = false;

  /// What answers isn't a Hue Bridge.
  bool stranger = false;

  /// The certificate shown, as after the bridge was swapped for another.
  String shown = certificate;

  int get listening => links.where((l) => l.listening).length;

  HueLink connect(String host, {String? key, String? pin}) {
    hosts.add(host);
    final link = FakeHueLink(this, key, pin);
    links.add(link);
    return link;
  }

  /// Changes a light as if someone used it, and tells who is listening.
  void change(String id, Map<String, dynamic> fields) {
    final change = {'id': id, 'type': 'light', ...fields};
    lights[id] = {...?lights[id], ...fields};
    for (final l in links) {
      l._tell(change);
    }
  }

  /// A bulb switched off at the wall, or back.
  void reach(String id, {required bool connected}) {
    connected ? lost.remove('dev-$id') : lost.add('dev-$id');
    for (final l in links) {
      l._tell({
        'id': 'zc-$id',
        'type': 'zigbee_connectivity',
        'owner': {'rid': 'dev-$id', 'rtype': 'device'},
        'status': connected ? 'connected' : 'connectivity_issue',
      });
    }
  }

  /// Drops every event stream, as when the bridge restarts.
  void restart() {
    for (final l in links) {
      l._drop();
    }
  }
}

class FakeHueLink implements HueLink {
  FakeHueLink(this.bridge, this.key, this.pin);
  final FakeHue bridge;
  final String? key;
  final String? pin;
  StreamController<Map<String, dynamic>>? _events;
  bool closed = false;

  bool get listening => _events != null && !closed;

  @override
  String? seenCertificate;

  void _check() {
    if (bridge.down || closed) {
      throw const HueException(HueFailure.unreachable, 'refused');
    }
    seenCertificate = bridge.shown;
    if (pin != null && pin != bridge.shown) {
      throw const HueException(HueFailure.changed);
    }
    if (bridge.stranger) throw const HueException(HueFailure.notHue);
  }

  @override
  Future<Object?> request(String method, String path, [Object? body]) async {
    await Future<void>.delayed(Duration.zero);
    _check();
    if (method == 'POST' && path == '/api') {
      return [
        bridge.pressed
            ? {
                'success': {'username': FakeHue.key},
              }
            : {
                'error': {
                  'type': 101,
                  'description': 'link button not pressed',
                },
              },
      ];
    }
    if (key != FakeHue.key) throw const HueException(HueFailure.badKey);
    if (method == 'GET' && path == '/clip/v2/resource/light') {
      return {'errors': <Object>[], 'data': bridge.lights.values.toList()};
    }
    if (method == 'GET' && path == '/clip/v2/resource/zigbee_connectivity') {
      return {
        'errors': <Object>[],
        'data': [
          for (final l in bridge.lights.values)
            {
              'id': 'zc-${l['id']}',
              'type': 'zigbee_connectivity',
              'owner': l['owner'],
              'status': bridge.lost.contains((l['owner'] as Map)['rid'])
                  ? 'connectivity_issue'
                  : 'connected',
            },
        ],
      };
    }
    const prefix = '/clip/v2/resource/light/';
    if (method == 'PUT' && path.startsWith(prefix)) {
      final id = path.substring(prefix.length);
      if (!bridge.lights.containsKey(id)) {
        return {
          'errors': [
            {'description': 'Not found'},
          ],
          'data': <Object>[],
        };
      }
      final fields = Map<String, dynamic>.from(body! as Map);
      bridge.puts.add((id, fields));
      scheduleMicrotask(() => bridge.change(id, fields));
      return {'errors': <Object>[], 'data': <Object>[]};
    }
    throw const HueException(HueFailure.notHue);
  }

  @override
  Stream<Map<String, dynamic>> events() {
    final events = _events = StreamController<Map<String, dynamic>>();
    try {
      _check();
      if (key != FakeHue.key) throw const HueException(HueFailure.badKey);
    } on HueException catch (e) {
      events.addError(e);
      events.close();
    }
    return events.stream;
  }

  void _tell(Map<String, dynamic> change) {
    final events = _events;
    if (events != null && !events.isClosed) events.add(change);
  }

  void _drop() {
    _events?.close();
    _events = null;
  }

  @override
  void close() {
    closed = true;
    _events?.close();
  }
}
