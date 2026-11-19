import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// The wire format Tuya / Smart Life devices speak on the home network
/// (TCP 6668, UDP 6666 and 6667), versions 3.3, 3.4 and 3.5. Nothing here
/// touches the network: bytes in, bytes out, so every part is tested
/// against fixed vectors.
///
/// - 3.3: `55AA` frame, payload AES-ECB with the device's local key, CRC32.
/// - 3.4: `55AA` frame, payload AES-ECB with a session key, HMAC-SHA256.
/// - 3.5: `6699` frame, AES-GCM with a session key.
enum TuyaVersion {
  v33('3.3'),
  v34('3.4'),
  v35('3.5');

  const TuyaVersion(this.text);
  final String text;

  /// The version a device announces. 3.2 devices speak 3.3. Null for one
  /// this app can't talk to (3.1 and older, or newer than 3.5).
  static TuyaVersion? parse(Object? text) => switch (text) {
    '3.2' || '3.3' => v33,
    '3.4' => v34,
    '3.5' => v35,
    _ => null,
  };

  /// 3.4 and 3.5 agree on a session key before anything else.
  bool get negotiates => this != v33;

  /// "3.x" and twelve zero bytes, in front of commands that carry it.
  Uint8List get header => Uint8List(15)..setAll(0, ascii.encode(text));
}

/// Command numbers of the local protocol.
abstract final class TuyaCommand {
  static const sessionStart = 3;
  static const sessionResponse = 4;
  static const sessionFinish = 5;
  static const control = 7;
  static const status = 8;
  static const heartbeat = 9;
  static const query = 10;
  static const controlNew = 13;
  static const queryNew = 16;
  static const refresh = 18;
  static const requestInfo = 0x25;

  /// Sent without the "3.x" header.
  static const _bare = {
    query,
    queryNew,
    refresh,
    heartbeat,
    sessionStart,
    sessionResponse,
    sessionFinish,
  };
  static bool hasHeader(int command) => !_bare.contains(command);
}

/// A frame that can't be read: cut short, wrong checksum, or sealed with
/// another key.
class TuyaFormatException implements Exception {
  const TuyaFormatException(this.message);
  final String message;
  @override
  String toString() => 'TuyaFormatException: $message';
}

/// One message, outside its frame. [payload] is plain: the frame's
/// encryption is already removed (3.5) or is the caller's job (3.3, 3.4).
class TuyaFrame {
  const TuyaFrame({
    required this.sequence,
    required this.command,
    required this.payload,
    this.returnCode,
  });

  final int sequence;
  final int command;

  /// Only in frames a device sends.
  final int? returnCode;
  final Uint8List payload;
}

const _prefix55aa = 0x000055AA;
const _suffix55aa = 0x0000AA55;
const _prefix6699 = 0x00006699;
const _suffix6699 = 0x00009966;

/// The key every device seals its "here I am" broadcasts with.
final Uint8List tuyaBroadcastKey = MD5Digest().process(
  Uint8List.fromList(ascii.encode('yGAdlopoPVldABfn')),
);

final _random = Random.secure();

Uint8List tuyaRandomBytes(int length) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) _random.nextInt(256)]);

Uint8List _concat(List<List<int>> parts) {
  final out = BytesBuilder(copy: false);
  for (final p in parts) {
    out.add(p);
  }
  return out.toBytes();
}

Uint8List _u32(int value) =>
    (ByteData(4)..setUint32(0, value)).buffer.asUint8List();

int _readU32(Uint8List data, int offset) =>
    ByteData.sublistView(data).getUint32(offset);

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

final List<int> _crcTable = [
  for (var n = 0; n < 256; n++)
    () {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      return c;
    }(),
];

int tuyaCrc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

Uint8List tuyaHmac(Uint8List key, List<int> data) {
  final mac = HMac(SHA256Digest(), 64)..init(KeyParameter(key));
  return mac.process(Uint8List.fromList(data));
}

Uint8List _ecb(Uint8List key, Uint8List data, {required bool encrypt}) {
  if (data.length % 16 != 0) {
    throw const TuyaFormatException('Not whole AES blocks');
  }
  final cipher = ECBBlockCipher(AESEngine())..init(encrypt, KeyParameter(key));
  final out = Uint8List(data.length);
  for (var offset = 0; offset < data.length; offset += 16) {
    cipher.processBlock(data, offset, out, offset);
  }
  return out;
}

/// AES-ECB with PKCS7 padding ([pad] false: [data] is whole blocks already).
Uint8List tuyaEcbEncrypt(Uint8List key, List<int> data, {bool pad = true}) {
  var plain = Uint8List.fromList(data);
  if (pad) {
    final n = 16 - plain.length % 16;
    plain = _concat([plain, List.filled(n, n)]);
  }
  return _ecb(key, plain, encrypt: true);
}

/// Undoes [tuyaEcbEncrypt], padding included.
Uint8List tuyaEcbDecrypt(Uint8List key, List<int> data) {
  if (data.isEmpty) throw const TuyaFormatException('Nothing to decrypt');
  final plain = _ecb(key, Uint8List.fromList(data), encrypt: false);
  final n = plain.last;
  if (n < 1 || n > 16) throw const TuyaFormatException('Wrong padding');
  return Uint8List.sublistView(plain, 0, plain.length - n);
}

/// AES-GCM: the ciphertext with its 16-byte tag at the end.
Uint8List tuyaGcmEncrypt(
  Uint8List key,
  Uint8List iv,
  List<int> data, {
  List<int> aad = const [],
}) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(KeyParameter(key), 128, iv, Uint8List.fromList(aad)),
    );
  return cipher.process(Uint8List.fromList(data));
}

Uint8List tuyaGcmDecrypt(
  Uint8List key,
  Uint8List iv,
  List<int> sealed, {
  List<int> aad = const [],
}) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(KeyParameter(key), 128, iv, Uint8List.fromList(aad)),
    );
  try {
    return cipher.process(Uint8List.fromList(sealed));
  } on Object {
    throw const TuyaFormatException('Sealed with another key');
  }
}

/// A `55AA` frame (3.3 and 3.4). [payload] is already encrypted. With
/// [hmacKey] the frame ends in an HMAC-SHA256 (3.4), without in a CRC32.
/// [returnCode] is set only by a device (and by the tests' fake device).
Uint8List tuyaPack55aa({
  required int sequence,
  required int command,
  required List<int> payload,
  Uint8List? hmacKey,
  int? returnCode,
}) {
  final body = _concat([if (returnCode != null) _u32(returnCode), payload]);
  final checkLength = hmacKey == null ? 4 : 32;
  final head = _concat([
    _u32(_prefix55aa),
    _u32(sequence),
    _u32(command),
    _u32(body.length + checkLength + 4),
    body,
  ]);
  final check = hmacKey == null
      ? _u32(tuyaCrc32(head))
      : tuyaHmac(hmacKey, head);
  return _concat([head, check, _u32(_suffix55aa)]);
}

/// A `6699` frame (3.5): [payload] is plain and sealed here with [key].
Uint8List tuyaPack6699({
  required int sequence,
  required int command,
  required List<int> payload,
  required Uint8List key,
  int? returnCode,
  Uint8List? iv,
}) {
  final nonce = iv ?? tuyaRandomBytes(12);
  final plain = _concat([if (returnCode != null) _u32(returnCode), payload]);
  final header = _concat([
    [0, 0],
    _u32(sequence),
    _u32(command),
    _u32(12 + plain.length + 16),
  ]);
  final sealed = tuyaGcmEncrypt(key, nonce, plain, aad: header);
  return _concat([_u32(_prefix6699), header, nonce, sealed, _u32(_suffix6699)]);
}

/// Splits a byte stream into frames. Bytes of a frame that hasn't fully
/// arrived wait for the next [add].
class TuyaFrameReader {
  var _buffer = Uint8List(0);

  /// The whole frames in the stream so far, still sealed.
  List<Uint8List> add(List<int> bytes) {
    _buffer = _concat([_buffer, bytes]);
    final frames = <Uint8List>[];
    while (true) {
      final start = _findPrefix();
      if (start < 0) {
        // Keep a tail that may be the start of a prefix.
        if (_buffer.length > 3) {
          _buffer = Uint8List.sublistView(_buffer, _buffer.length - 3);
        }
        break;
      }
      if (start > 0) _buffer = Uint8List.sublistView(_buffer, start);
      final total = tuyaFrameLength(_buffer);
      if (total == null || _buffer.length < total) break;
      frames.add(Uint8List.fromList(Uint8List.sublistView(_buffer, 0, total)));
      _buffer = Uint8List.sublistView(_buffer, total);
    }
    return frames;
  }

  int _findPrefix() {
    for (var i = 0; i + 4 <= _buffer.length; i++) {
      if (_buffer[i] != 0 || _buffer[i + 1] != 0) continue;
      final a = _buffer[i + 2], b = _buffer[i + 3];
      if ((a == 0x55 && b == 0xAA) || (a == 0x66 && b == 0x99)) return i;
    }
    return -1;
  }
}

/// The length of the frame that starts [data], or null when its header
/// hasn't fully arrived.
int? tuyaFrameLength(Uint8List data) {
  if (data.length < 4) return null;
  final prefix = _readU32(data, 0);
  final int length;
  final int total;
  if (prefix == _prefix55aa) {
    if (data.length < 16) return null;
    length = _readU32(data, 12);
    total = 16 + length;
  } else if (prefix == _prefix6699) {
    if (data.length < 18) return null;
    length = _readU32(data, 14);
    total = 18 + length + 4;
  } else {
    throw const TuyaFormatException('Not a Tuya frame');
  }
  // Real frames are a few hundred bytes.
  if (length > 4096) throw const TuyaFormatException('Frame too long');
  return total;
}

/// Opens one whole frame.
///
/// - `55AA`: checks the CRC32, or the HMAC when [key] is given (3.4). The
///   payload is returned as sent, still AES-ECB encrypted.
/// - `6699`: [key] is required; the payload is returned decrypted.
///
/// [fromDevice] frames carry a return code in front of the payload.
TuyaFrame tuyaUnpack(
  Uint8List data, {
  Uint8List? key,
  bool fromDevice = true,
  bool hmac = false,
}) {
  final total = tuyaFrameLength(data);
  if (total == null || data.length < total) {
    throw const TuyaFormatException('Frame cut short');
  }
  final prefix = _readU32(data, 0);
  if (prefix == _prefix55aa) {
    final checkLength = hmac ? 32 : 4;
    final bodyEnd = total - checkLength - 4;
    final bodyStart = 16;
    if (bodyEnd < bodyStart) throw const TuyaFormatException('Frame too short');
    final signed = Uint8List.sublistView(data, 0, bodyEnd);
    final check = Uint8List.sublistView(data, bodyEnd, bodyEnd + checkLength);
    if (hmac) {
      if (key == null) throw ArgumentError('An HMAC frame needs a key');
      if (!_same(check, tuyaHmac(key, signed))) {
        throw const TuyaFormatException('Wrong HMAC');
      }
    } else if (_readU32(check, 0) != tuyaCrc32(signed)) {
      throw const TuyaFormatException('Wrong CRC');
    }
    var body = Uint8List.sublistView(data, bodyStart, bodyEnd);
    int? returnCode;
    if (fromDevice) {
      if (body.length < 4) throw const TuyaFormatException('No return code');
      returnCode = _readU32(body, 0);
      body = Uint8List.sublistView(body, 4);
    }
    return TuyaFrame(
      sequence: _readU32(data, 4),
      command: _readU32(data, 8),
      returnCode: returnCode,
      payload: Uint8List.fromList(body),
    );
  }
  if (key == null) throw ArgumentError('A 6699 frame needs a key');
  if (total < 18 + 12 + 16 + 4) {
    throw const TuyaFormatException('Frame too short');
  }
  var plain = tuyaGcmDecrypt(
    key,
    Uint8List.sublistView(data, 18, 30),
    Uint8List.sublistView(data, 30, total - 4),
    aad: Uint8List.sublistView(data, 4, 18),
  );
  int? returnCode;
  if (fromDevice) {
    if (plain.length < 4) throw const TuyaFormatException('No return code');
    returnCode = _readU32(plain, 0);
    plain = Uint8List.sublistView(plain, 4);
  }
  return TuyaFrame(
    sequence: _readU32(data, 6),
    command: _readU32(data, 10),
    returnCode: returnCode,
    payload: Uint8List.fromList(plain),
  );
}

/// The JSON object inside a decrypted payload, whatever stands in front of
/// it (the "3.x" header). Null when there is none (a plain acknowledgement).
Map<String, dynamic>? tuyaJson(List<int> plain) {
  final text = utf8.decode(plain, allowMalformed: true);
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final decoded = jsonDecode(text.substring(start, end + 1));
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } on FormatException {
    return null;
  }
}

/// What a plug says about itself on the network every few seconds.
class TuyaAnnouncement {
  const TuyaAnnouncement({
    required this.deviceId,
    required this.ip,
    required this.versionText,
    this.productKey,
  });

  final String deviceId;
  final String ip;

  /// As announced: "3.3", "3.4"... See [TuyaVersion.parse].
  final String versionText;
  final String? productKey;

  TuyaVersion? get version => TuyaVersion.parse(versionText);
}

/// Reads a discovery broadcast (UDP 6666 or 6667). Null for anything that
/// isn't one.
TuyaAnnouncement? tuyaParseAnnouncement(Uint8List datagram) {
  try {
    Map<String, dynamic>? json;
    if (datagram.length >= 4 && _readU32(datagram, 0) == _prefix6699) {
      // The return code is there or not, depending on the sender.
      final frame = tuyaUnpack(
        datagram,
        key: tuyaBroadcastKey,
        fromDevice: false,
      );
      json = tuyaJson(frame.payload);
    } else if (datagram.length >= 4 && _readU32(datagram, 0) == _prefix55aa) {
      final payload = tuyaUnpack(datagram).payload;
      json = payload.isNotEmpty && payload.first == 0x7B
          ? tuyaJson(payload)
          : tuyaJson(tuyaEcbDecrypt(tuyaBroadcastKey, payload));
    } else {
      json = tuyaJson(tuyaEcbDecrypt(tuyaBroadcastKey, datagram));
    }
    final id = json?['gwId'];
    final ip = json?['ip'];
    if (id is! String || id.isEmpty || ip is! String || ip.isEmpty) return null;
    return TuyaAnnouncement(
      deviceId: id,
      ip: ip,
      versionText: '${json?['version'] ?? ''}',
      productKey: json?['productKey'] as String?,
    );
  } on Object {
    return null;
  }
}

/// "Announce yourselves", broadcast to UDP 7000: 3.5 devices only answer
/// when asked. [ip] is this phone's address on the network.
Uint8List tuyaInfoRequest(String ip) => tuyaPack6699(
  sequence: 0,
  command: TuyaCommand.requestInfo,
  payload: utf8.encode(jsonEncode({'from': 'app', 'ip': ip})),
  key: tuyaBroadcastKey,
);

/// The messages of one connection to one device: builds what the app
/// sends and opens what the device sends back, for its protocol version.
/// The socket is someone else's job (see `TuyaLink`).
class TuyaCodec {
  TuyaCodec({
    required this.version,
    required this.deviceId,
    required Uint8List localKey,
    int Function()? now,
  }) : _localKey = localKey,
       _key = localKey,
       _clock = now {
    if (localKey.length != 16) {
      throw ArgumentError('A Tuya local key is 16 bytes');
    }
  }

  final TuyaVersion version;
  final String deviceId;
  final Uint8List _localKey;

  /// The local key, then the session key once agreed (3.4, 3.5).
  Uint8List _key;
  var _sequence = 1;
  Uint8List? _localNonce;

  /// Some devices with a 22-character id only answer a query sent as a
  /// control command that lists the data points wanted.
  bool queryAsControl = false;

  /// Seconds since 1970; tests pass a fixed one.
  final int Function()? _clock;
  int _now() => _clock?.call() ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Uint8List _frame(int command, List<int> plain) {
    final sequence = _sequence++;
    switch (version) {
      case TuyaVersion.v33:
        final sealed = tuyaEcbEncrypt(_key, plain);
        return tuyaPack55aa(
          sequence: sequence,
          command: command,
          payload: TuyaCommand.hasHeader(command)
              ? _concat([version.header, sealed])
              : sealed,
        );
      case TuyaVersion.v34:
        final body = TuyaCommand.hasHeader(command)
            ? _concat([version.header, plain])
            : plain;
        return tuyaPack55aa(
          sequence: sequence,
          command: command,
          payload: tuyaEcbEncrypt(_key, body),
          hmacKey: _key,
        );
      case TuyaVersion.v35:
        return tuyaPack6699(
          sequence: sequence,
          command: command,
          payload: TuyaCommand.hasHeader(command)
              ? _concat([version.header, plain])
              : plain,
          key: _key,
        );
    }
  }

  Uint8List _json(int command, Map<String, dynamic> body) =>
      _frame(command, utf8.encode(jsonEncode(body)));

  /// The command a device answers a [query] with.
  int get queryCommand => switch (version) {
    TuyaVersion.v33 =>
      queryAsControl ? TuyaCommand.controlNew : TuyaCommand.query,
    _ => TuyaCommand.queryNew,
  };

  /// The command a device acknowledges a [control] with.
  int get controlCommand => switch (version) {
    TuyaVersion.v33 => TuyaCommand.control,
    _ => TuyaCommand.controlNew,
  };

  /// "Send me all your data points."
  Uint8List query() {
    if (version != TuyaVersion.v33) return _json(TuyaCommand.queryNew, {});
    if (queryAsControl) {
      return _json(TuyaCommand.controlNew, {
        'devId': deviceId,
        'uid': deviceId,
        't': '${_now()}',
        'dps': {'1': null},
      });
    }
    return _json(TuyaCommand.query, {
      'gwId': deviceId,
      'devId': deviceId,
      'uid': deviceId,
      't': '${_now()}',
    });
  }

  /// "Set these data points", for example `{'1': true}` to switch on.
  Uint8List control(Map<String, dynamic> dps) {
    if (version == TuyaVersion.v33) {
      return _json(TuyaCommand.control, {
        'devId': deviceId,
        'uid': deviceId,
        't': '${_now()}',
        'dps': dps,
      });
    }
    return _json(TuyaCommand.controlNew, {
      'protocol': 5,
      't': _now(),
      'data': {'dps': dps},
    });
  }

  /// Keeps the connection open; devices drop a silent one.
  Uint8List heartbeat() =>
      _json(TuyaCommand.heartbeat, {'gwId': deviceId, 'devId': deviceId});

  /// "Measure these data points again now" (power readings).
  Uint8List refresh(List<int> dpIds) =>
      _json(TuyaCommand.refresh, {'dpId': dpIds});

  /// Step 1 of agreeing a session key: this side's nonce.
  Uint8List sessionStart({Uint8List? nonce}) {
    _key = _localKey;
    final local = nonce ?? tuyaRandomBytes(16);
    _localNonce = local;
    return _frame(TuyaCommand.sessionStart, local);
  }

  /// Steps 2 and 3: checks the device's answer to [sessionStart] and
  /// returns the frame that finishes the exchange. From then on every
  /// message uses the session key. Throws [TuyaFormatException] when the
  /// device has another local key.
  Uint8List sessionFinish(Uint8List response) {
    final local = _localNonce;
    if (local == null) throw StateError('sessionStart comes first');
    final frame = _open(response);
    if (frame.command != TuyaCommand.sessionResponse) {
      throw const TuyaFormatException('Not a session answer');
    }
    final plain = version == TuyaVersion.v34
        ? tuyaEcbDecrypt(_localKey, frame.payload)
        : frame.payload;
    if (plain.length < 48) {
      throw const TuyaFormatException('Session answer too short');
    }
    final remote = Uint8List.sublistView(plain, 0, 16);
    if (!_same(
      Uint8List.sublistView(plain, 16, 48),
      tuyaHmac(_localKey, local),
    )) {
      throw const TuyaFormatException('The device has another local key');
    }
    final finish = _frame(
      TuyaCommand.sessionFinish,
      tuyaHmac(_localKey, remote),
    );
    final mixed = Uint8List.fromList([
      for (var i = 0; i < 16; i++) local[i] ^ remote[i],
    ]);
    _key = version == TuyaVersion.v34
        ? tuyaEcbEncrypt(_localKey, mixed, pad: false)
        : Uint8List.sublistView(
            tuyaGcmEncrypt(
              _localKey,
              Uint8List.sublistView(local, 0, 12),
              mixed,
            ),
            0,
            16,
          );
    return finish;
  }

  TuyaFrame _open(Uint8List frame) =>
      tuyaUnpack(frame, key: _key, hmac: version == TuyaVersion.v34);

  /// Opens a frame from the device: its command and the JSON it carries
  /// (null for a plain acknowledgement). Throws [TuyaFormatException] when
  /// it can't be read with this key. `refused` is the "data unvalid" answer
  /// some devices give a plain query (see [queryAsControl]).
  ({int command, Map<String, dynamic>? json, bool refused}) read(
    Uint8List frame,
  ) {
    final opened = _open(frame);
    var payload = opened.payload;
    if (payload.isEmpty) {
      return (command: opened.command, json: null, refused: false);
    }
    if (version == TuyaVersion.v33) {
      final header = version.header;
      if (payload.length >= 15 &&
          _same(Uint8List.sublistView(payload, 0, 3), header.sublist(0, 3))) {
        payload = Uint8List.sublistView(payload, 15);
      }
      if (payload.isEmpty) {
        return (command: opened.command, json: null, refused: false);
      }
      payload = tuyaEcbDecrypt(_key, payload);
    } else if (version == TuyaVersion.v34) {
      payload = tuyaEcbDecrypt(_key, payload);
    }
    return (
      command: opened.command,
      json: tuyaJson(payload),
      // What a device that wants [queryAsControl] answers a plain query.
      refused: utf8
          .decode(payload, allowMalformed: true)
          .contains('data unvalid'),
    );
  }
}

/// The data points in a device's message: `dps`, or `data.dps` (3.4+).
Map<String, dynamic>? tuyaDps(Map<String, dynamic>? json) {
  if (json == null) return null;
  final direct = json['dps'];
  if (direct is Map) return Map<String, dynamic>.from(direct);
  final data = json['data'];
  if (data is Map && data['dps'] is Map) {
    return Map<String, dynamic>.from(data['dps'] as Map);
  }
  return null;
}

/// A local key as typed: 16 characters, used as they are.
Uint8List? tuyaParseLocalKey(String text) {
  final bytes = utf8.encode(text.trim());
  return bytes.length == 16 ? Uint8List.fromList(bytes) : null;
}
