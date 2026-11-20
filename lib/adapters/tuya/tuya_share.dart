import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// "Link Smart Life once": a short sign-in to Tuya's cloud that reads the
/// local keys of the account's devices, so nobody has to copy them from
/// iot.tuya.com. After that the cloud isn't used: [TuyaShare.signOut] ends
/// the session and the devices are talked to over the Wi-Fi only.
///
/// This is the sign-in Tuya made for Home Assistant (a user code from the
/// Smart Life app plus a QR code scanned in it), spoken the way Tuya's own
/// open library, tuya-device-sharing-sdk, speaks it. Tuya gives it no other
/// app name, so the cloud sees this app under Home Assistant's.
const tuyaShareClientId = 'HA_3y9q4ak7g4ephrvke';
const tuyaShareSchema = 'haauthorize';
const _loginHost = 'apigw.iotbing.com';

enum TuyaShareFailure {
  /// Tuya's cloud couldn't be reached.
  offline,

  /// The user code isn't one Tuya knows.
  badUserCode,

  /// The QR code wasn't scanned and approved in time.
  expired,

  /// The cloud refused the request.
  refused,
}

class TuyaShareException implements Exception {
  const TuyaShareException(this.failure, [this.detail = '']);
  final TuyaShareFailure failure;
  final String detail;
  @override
  String toString() => 'TuyaShareException(${failure.name}: $detail)';
}

/// One HTTPS request to Tuya's cloud, answered with the decoded JSON body.
/// The real one is [tuyaShareSend]; tests give their own.
typedef TuyaShareSend =
    Future<Map<String, dynamic>> Function(
      String method,
      Uri uri, {
      Map<String, String> headers,
      Object? body,
    });

Future<Map<String, dynamic>> tuyaShareSend(
  String method,
  Uri uri, {
  Map<String, String> headers = const {},
  Object? body,
}) async {
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await http.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 15));
    final text = await utf8.decodeStream(response);
    final answer = jsonDecode(text);
    if (answer is! Map<String, dynamic>) {
      throw TuyaShareException(
        TuyaShareFailure.refused,
        'HTTP ${response.statusCode}',
      );
    }
    return answer;
  } on TuyaShareException {
    rethrow;
  } on FormatException catch (e) {
    throw TuyaShareException(TuyaShareFailure.refused, e.message);
  } on Object catch (e) {
    throw TuyaShareException(TuyaShareFailure.offline, '$e');
  } finally {
    http.close(force: true);
  }
}

/// A device of the Smart Life account, as the cloud lists it.
class TuyaSharedDevice {
  const TuyaSharedDevice({
    required this.deviceId,
    required this.name,
    required this.localKey,
    this.sub = false,
  });

  final String deviceId;
  final String name;
  final String localKey;

  /// Behind a hub (Zigbee, Bluetooth), so not reachable over the Wi-Fi by
  /// itself.
  final bool sub;

  static TuyaSharedDevice? from(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final key = json['local_key'];
    if (id is! String || id.isEmpty || key is! String || key.isEmpty) {
      return null;
    }
    final name = json['name'];
    return TuyaSharedDevice(
      deviceId: id,
      name: name is String ? name.trim() : '',
      localKey: key,
      sub: json['sub'] == true,
    );
  }
}

/// The signed-in session, held in memory until [TuyaShare.signOut].
class TuyaShareSession {
  const TuyaShareSession({
    required this.endpoint,
    required this.accessToken,
    required this.refreshToken,
    required this.terminalId,
  });
  final String endpoint;
  final String accessToken;
  final String refreshToken;
  final String terminalId;
}

class TuyaShare {
  TuyaShare({TuyaShareSend? send, Random? random, DateTime Function()? now})
    : _send = send ?? tuyaShareSend,
      _random = random ?? Random.secure(),
      _now = now ?? DateTime.now;

  final TuyaShareSend _send;
  final Random _random;
  final DateTime Function() _now;

  /// What the QR code shown to the Smart Life app says.
  static String qrText(String token) => 'tuyaSmart--qrLogin?token=$token';

  /// Asks for a sign-in token for the account with [userCode].
  Future<String> start(String userCode) async {
    final answer = await _send(
      'POST',
      Uri.https(_loginHost, '/v1.0/m/life/home-assistant/qrcode/tokens', {
        'clientid': tuyaShareClientId,
        'usercode': userCode,
        'schema': tuyaShareSchema,
      }),
    );
    final result = answer['result'];
    final token = result is Map ? result['qrcode'] : null;
    if (answer['success'] != true || token is! String || token.isEmpty) {
      throw TuyaShareException(
        TuyaShareFailure.badUserCode,
        '${answer['msg'] ?? answer['code'] ?? ''}',
      );
    }
    return token;
  }

  /// Whether the code was scanned and approved yet: the session once it
  /// was, null while it wasn't.
  Future<TuyaShareSession?> check(String token, String userCode) async {
    final answer = await _send(
      'GET',
      Uri.https(
        _loginHost,
        '/v1.0/m/life/home-assistant/qrcode/tokens/$token',
        {'clientid': tuyaShareClientId, 'usercode': userCode},
      ),
    );
    final result = answer['result'];
    if (answer['success'] != true || result is! Map) return null;
    final endpoint = result['endpoint'];
    final access = result['access_token'];
    final refresh = result['refresh_token'];
    if (endpoint is! String || access is! String || refresh is! String) {
      return null;
    }
    final terminal = result['terminal_id'];
    return TuyaShareSession(
      endpoint: endpoint,
      accessToken: access,
      refreshToken: refresh,
      terminalId: terminal is String ? terminal : '',
    );
  }

  /// Waits until the code is approved in the Smart Life app. Throws
  /// [TuyaShareFailure.expired] after [timeout]; [stopped] ends the wait
  /// early (with null).
  Future<TuyaShareSession?> wait(
    String token,
    String userCode, {
    Duration every = const Duration(seconds: 2),
    Duration timeout = const Duration(minutes: 3),
    bool Function()? stopped,
  }) async {
    final end = _now().add(timeout);
    while (_now().isBefore(end)) {
      if (stopped?.call() ?? false) return null;
      try {
        final session = await check(token, userCode);
        if (session != null) return session;
      } on TuyaShareException catch (e) {
        // A dropped connection while waiting: the next try may get through.
        if (e.failure != TuyaShareFailure.offline) rethrow;
      }
      await Future<void>.delayed(every);
    }
    throw const TuyaShareException(TuyaShareFailure.expired);
  }

  /// Every device of the account that has a local key, over all its homes.
  Future<List<TuyaSharedDevice>> devices(TuyaShareSession session) async {
    final homes = await _request(session, 'GET', '/v1.0/m/life/users/homes');
    final devices = <String, TuyaSharedDevice>{};
    for (final home in homes is List ? homes : const <Object?>[]) {
      final id = home is Map ? home['ownerId'] : null;
      if (id == null) continue;
      final list = await _request(
        session,
        'GET',
        '/v1.0/m/life/ha/home/devices',
        query: {'homeId': '$id'},
      );
      for (final json in list is List ? list : const <Object?>[]) {
        final device = TuyaSharedDevice.from(json);
        if (device != null) devices[device.deviceId] = device;
      }
    }
    return devices.values.toList();
  }

  /// Ends the session at Tuya's cloud. Failing is fine: the tokens are
  /// dropped here either way and run out by themselves.
  Future<void> signOut(TuyaShareSession session) async {
    try {
      await _request(
        session,
        'POST',
        '/v1.0/m/token/terminal/expire',
        body: {
          'accessToken': session.accessToken,
          'terminalId': session.terminalId,
        },
      );
    } on TuyaShareException {
      // See above.
    }
  }

  Future<Object?> _request(
    TuyaShareSession session,
    String method,
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? body,
  }) async {
    final requestId = _uuid();
    final sealer = TuyaShareSealer(requestId, session.refreshToken);
    final queryData = query == null
        ? ''
        : sealer.seal(jsonEncode(query), _nonce());
    final bodyData = body == null
        ? ''
        : sealer.seal(jsonEncode(body), _nonce());
    final headers = {
      'X-appKey': tuyaShareClientId,
      'X-requestId': requestId,
      'X-sid': '',
      'X-time': '${_now().millisecondsSinceEpoch}',
      'X-token': session.accessToken,
    };
    headers['X-sign'] = sealer.sign(headers, queryData, bodyData);
    final base = Uri.parse(session.endpoint);
    final answer = await _send(
      method,
      base.replace(
        path: path,
        queryParameters: queryData.isEmpty ? null : {'encdata': queryData},
      ),
      headers: headers,
      body: bodyData.isEmpty ? null : {'encdata': bodyData},
    );
    if (answer['success'] != true) {
      throw TuyaShareException(
        TuyaShareFailure.refused,
        '${answer['msg'] ?? answer['code'] ?? ''}',
      );
    }
    final result = answer['result'];
    if (result is! String || result.isEmpty) return result;
    final text = sealer.open(result);
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  static const _alphabet = 'ABCDEFGHJKMNPQRSTWXYZabcdefhijkmnprstwxyz2345678';

  String _nonce() => String.fromCharCodes([
    for (var i = 0; i < 12; i++)
      _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
  ]);

  String _uuid() {
    final b = [for (var i = 0; i < 16; i++) _random.nextInt(256)];
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = _hex(b);
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }
}

/// The per-request encryption and signature of Tuya's sharing API: both keys
/// come from the request id and the session's refresh token.
class TuyaShareSealer {
  TuyaShareSealer(String requestId, String refreshToken)
    : hashKey = _hex(MD5Digest().process(_utf8('$requestId$refreshToken'))) {
    secret = _hex(_hmac(_utf8(requestId), _utf8(hashKey))).substring(0, 16);
  }

  final String hashKey;
  late final String secret;

  /// AES-GCM of [text] under [nonce] (12 characters), as two base64 parts.
  String seal(String text, String nonce) {
    final sealed = _gcm(true, _utf8(nonce), _utf8(text));
    return base64Encode(_utf8(nonce)) + base64Encode(sealed);
  }

  /// Opens an answer: base64 of the nonce followed by the sealed text.
  String open(String sealed) {
    final Uint8List bytes;
    try {
      bytes = base64Decode(sealed);
      if (bytes.length < 28) throw const FormatException('Too short');
      return utf8.decode(_gcm(false, bytes.sublist(0, 12), bytes.sublist(12)));
    } on Object catch (e) {
      throw TuyaShareException(TuyaShareFailure.refused, 'Unreadable: $e');
    }
  }

  String sign(Map<String, String> headers, String query, String body) {
    const signed = ['X-appKey', 'X-requestId', 'X-sid', 'X-time', 'X-token'];
    final text =
        [
          for (final name in signed)
            if ((headers[name] ?? '').isNotEmpty) '$name=${headers[name]}',
        ].join('||') +
        query +
        body;
    return _hex(_hmac(_utf8(hashKey), _utf8(text)));
  }

  Uint8List _gcm(bool seal, Uint8List nonce, Uint8List data) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        seal,
        AEADParameters(KeyParameter(_utf8(secret)), 128, nonce, Uint8List(0)),
      );
    return cipher.process(data);
  }
}

Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));

Uint8List _hmac(Uint8List key, Uint8List data) =>
    (HMac(SHA256Digest(), 64)..init(KeyParameter(key))).process(data);

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
