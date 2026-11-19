import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:zerotrust_home/adapters/tuya/tuya_codec.dart';

/// A Tuya plug on the loopback interface: speaks the device's side of
/// protocol 3.3, 3.4 or 3.5 over a real socket.
class FakeTuyaDevice {
  FakeTuyaDevice._(this._server, this.version, this.deviceId, this.localKey);

  static Future<FakeTuyaDevice> start({
    required TuyaVersion version,
    String deviceId = 'bf1234567890abcdefgh',
    String localKey = '0123456789abcdef',
    Map<String, dynamic>? dps,
  }) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final device = FakeTuyaDevice._(
      server,
      version,
      deviceId,
      Uint8List.fromList(ascii.encode(localKey)),
    );
    if (dps != null) device.dps.addAll(dps);
    server.listen(device._serve);
    return device;
  }

  final ServerSocket _server;
  final TuyaVersion version;
  final String deviceId;
  final Uint8List localKey;

  /// The plug's data points: 1 = on/off, 19 = power in tenths of a watt.
  final dps = <String, dynamic>{
    '1': false,
    '9': 0,
    '18': 0,
    '19': 0,
    '20': 2301,
  };

  /// Answers a plain query with "data unvalid", like some 22-character
  /// devices; they want the query as a control command.
  bool wantsQueryAsControl = false;

  /// Acknowledges a query with an empty frame, then sends the readings in
  /// a status frame, like some devices do.
  bool acknowledgesQueries = false;

  /// With [acknowledgesQueries]: sends nothing after the acknowledgement.
  bool nothingToReport = false;

  /// Stops answering heartbeats (the device hung).
  bool silent = false;

  final _clients = <Socket>[];
  final _keys = <Socket, Uint8List>{};
  var _sequence = 100;

  /// Commands received, in order.
  final received = <int>[];
  var connections = 0;

  String get host => _server.address.address;
  int get port => _server.port;

  bool get _hmac => version == TuyaVersion.v34;

  void _serve(Socket socket) {
    connections++;
    _clients.add(socket);
    _keys[socket] = localKey;
    final reader = TuyaFrameReader();
    Uint8List? remoteNonce;
    Uint8List? localNonce;
    socket.listen(
      (bytes) {
        for (final raw in reader.add(bytes)) {
          final TuyaFrame frame;
          try {
            frame = tuyaUnpack(
              raw,
              key: _keys[socket],
              hmac: _hmac,
              fromDevice: false,
            );
          } on TuyaFormatException {
            // Sealed with another key: a real device stays silent.
            continue;
          }
          received.add(frame.command);
          switch (frame.command) {
            case TuyaCommand.sessionStart:
              localNonce = version == TuyaVersion.v34
                  ? tuyaEcbDecrypt(localKey, frame.payload)
                  : frame.payload;
              remoteNonce = tuyaRandomBytes(16);
              _send(socket, TuyaCommand.sessionResponse, [
                ...remoteNonce!,
                ...tuyaHmac(localKey, localNonce!),
              ]);
            case TuyaCommand.sessionFinish:
              final mixed = Uint8List.fromList([
                for (var i = 0; i < 16; i++) localNonce![i] ^ remoteNonce![i],
              ]);
              _keys[socket] = version == TuyaVersion.v34
                  ? tuyaEcbEncrypt(localKey, mixed, pad: false)
                  : Uint8List.sublistView(
                      tuyaGcmEncrypt(
                        localKey,
                        Uint8List.sublistView(localNonce!, 0, 12),
                        mixed,
                      ),
                      0,
                      16,
                    );
            case TuyaCommand.query:
              final json = _plainJson(socket, frame);
              if (json == null) continue;
              if (wantsQueryAsControl) {
                _send(
                  socket,
                  TuyaCommand.query,
                  utf8.encode('json obj data unvalid'),
                );
              } else {
                _answerQuery(socket, TuyaCommand.query);
              }
            case TuyaCommand.queryNew:
              _answerQuery(socket, TuyaCommand.queryNew);
            case TuyaCommand.control || TuyaCommand.controlNew:
              final json = _plainJson(socket, frame);
              if (json == null) continue;
              final wanted = tuyaDps(json) ?? const {};
              if (wanted.values.every((v) => v == null)) {
                // A query sent as a control command.
                _sendJson(socket, frame.command, {'dps': dps});
                continue;
              }
              dps.addAll(wanted);
              _send(socket, frame.command, const []);
              push(wanted);
            case TuyaCommand.heartbeat:
              if (!silent) _send(socket, TuyaCommand.heartbeat, const []);
            case TuyaCommand.refresh:
              push({'19': dps['19']});
          }
        }
      },
      onDone: () => _clients.remove(socket),
      onError: (_) => _clients.remove(socket),
    );
  }

  void _answerQuery(Socket socket, int command) {
    if (!acknowledgesQueries) {
      _sendJson(socket, command, {'dps': dps});
      return;
    }
    _send(socket, command, const []);
    if (!nothingToReport) push(Map.of(dps));
  }

  /// The JSON a frame carries, or null when it wasn't sealed with the
  /// right key (3.3 has no check but the decryption itself).
  Map<String, dynamic>? _plainJson(Socket socket, TuyaFrame frame) {
    try {
      var payload = frame.payload;
      if (version == TuyaVersion.v33) {
        if (TuyaCommand.hasHeader(frame.command)) {
          payload = Uint8List.sublistView(payload, 15);
        }
        payload = tuyaEcbDecrypt(_keys[socket]!, payload);
      } else if (version == TuyaVersion.v34) {
        payload = tuyaEcbDecrypt(_keys[socket]!, payload);
      }
      return tuyaJson(payload);
    } on Object {
      return null;
    }
  }

  void _sendJson(
    Socket socket,
    int command,
    Map<String, dynamic> json, {
    bool header = false,
  }) => _send(socket, command, utf8.encode(jsonEncode(json)), header: header);

  void _send(
    Socket socket,
    int command,
    List<int> plain, {
    bool header = false,
  }) {
    final key = _keys[socket]!;
    final body = header ? [...version.header, ...plain] : plain;
    final Uint8List frame;
    switch (version) {
      case TuyaVersion.v33:
        frame = tuyaPack55aa(
          sequence: _sequence++,
          command: command,
          returnCode: 0,
          payload: plain.isEmpty
              ? const []
              : [if (header) ...version.header, ...tuyaEcbEncrypt(key, plain)],
        );
      case TuyaVersion.v34:
        frame = tuyaPack55aa(
          sequence: _sequence++,
          command: command,
          returnCode: 0,
          payload: tuyaEcbEncrypt(key, body),
          hmacKey: key,
        );
      case TuyaVersion.v35:
        frame = tuyaPack6699(
          sequence: _sequence++,
          command: command,
          returnCode: 0,
          payload: body,
          key: key,
        );
    }
    socket.add(frame);
  }

  /// Reports data points to every connected app, as the plug does when
  /// its button is pressed.
  void push(Map<String, dynamic> changed) {
    dps.addAll(changed);
    for (final socket in _clients.toList()) {
      final json = version == TuyaVersion.v33
          ? {'devId': deviceId, 'dps': changed}
          : {
              'protocol': 4,
              't': 1,
              'data': {'dps': changed},
            };
      _sendJson(socket, TuyaCommand.status, json, header: true);
    }
  }

  /// Drops every connection, like a plug pulled from the wall.
  Future<void> drop() async {
    for (final s in _clients.toList()) {
      s.destroy();
    }
    _clients.clear();
  }

  Future<void> stop() async {
    await drop();
    await _server.close();
  }
}
