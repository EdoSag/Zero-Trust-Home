import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'tuya_codec.dart';

/// Finds Tuya devices on the home network. Each one announces itself by
/// UDP broadcast every few seconds (3.5 devices when asked), with its id,
/// address and protocol version. The local key is never announced.
///
/// Listens only while someone listens to [watch].
class TuyaDiscovery {
  TuyaDiscovery({this.onStart, this.onStop});

  /// Called around listening: Android only delivers broadcasts to an app
  /// that holds a multicast lock.
  final Future<void> Function()? onStart;
  final Future<void> Function()? onStop;

  static const _listenPorts = [6666, 6667, 7000];
  static const _askPort = 7000;
  static const _askEvery = Duration(seconds: 6);

  final _found = <String, TuyaAnnouncement>{};
  final _sockets = <RawDatagramSocket>[];
  late final _controller =
      StreamController<Map<String, TuyaAnnouncement>>.broadcast(
        onListen: _start,
        onCancel: _stop,
      );
  Timer? _askTimer;
  var _running = false;

  /// Every device heard so far, by device id.
  Map<String, TuyaAnnouncement> get found => Map.unmodifiable(_found);

  /// The devices heard so far, again each time one appears or moves.
  Stream<Map<String, TuyaAnnouncement>> watch() async* {
    yield found;
    yield* _controller.stream;
  }

  /// Drops what was heard about a device: nothing answered at that address,
  /// so the saved one is tried again until the device announces itself anew.
  void forget(String deviceId) => _found.remove(deviceId);

  /// Takes one datagram; public so tests can feed it.
  void handle(List<int> datagram) {
    final a = tuyaParseAnnouncement(Uint8List.fromList(datagram));
    if (a == null) return;
    final old = _found[a.deviceId];
    if (old != null && old.ip == a.ip && old.versionText == a.versionText) {
      return;
    }
    _found[a.deviceId] = a;
    if (_controller.hasListener) _controller.add(found);
  }

  Future<void> _start() async {
    if (_running) return;
    _running = true;
    try {
      await onStart?.call();
    } on Object {
      // Without the lock some phones still deliver broadcasts.
    }
    for (final port in _listenPorts) {
      try {
        final socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          port,
          reuseAddress: true,
        );
        if (!_running) {
          socket.close();
          return;
        }
        socket.broadcastEnabled = true;
        socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          final datagram = socket.receive();
          if (datagram != null) handle(datagram.data);
        }, onError: (_) {});
        _sockets.add(socket);
      } on Object {
        // The port is taken (another smart home app): the others still work.
      }
    }
    unawaited(_ask());
    _askTimer = Timer.periodic(_askEvery, (_) => _ask());
  }

  /// Asks 3.5 devices to announce themselves.
  Future<void> _ask() async {
    final sender = _sockets.where((s) => s.port == _askPort).firstOrNull;
    if (sender == null) return;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.isLoopback) continue;
          sender.send(
            tuyaInfoRequest(address.address),
            InternetAddress('255.255.255.255'),
            _askPort,
          );
        }
      }
    } on Object {
      // No network right now.
    }
  }

  Future<void> _stop() async {
    if (!_running) return;
    _running = false;
    _askTimer?.cancel();
    _askTimer = null;
    for (final s in _sockets) {
      s.close();
    }
    _sockets.clear();
    try {
      await onStop?.call();
    } on Object {
      // Nothing to release.
    }
  }

  Future<void> dispose() async {
    await _stop();
    await _controller.close();
  }
}
