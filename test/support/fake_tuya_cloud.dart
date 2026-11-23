import 'dart:convert';

import 'package:zerotrust_home/adapters/tuya/tuya_share.dart';

/// Tuya's cloud, as far as "Link Smart Life" talks to it: the QR sign-in
/// and the sealed, signed device list. Checks every sealed request the way
/// the real one does.
class FakeTuyaCloud {
  static const userCode = 'Ab12Cd';
  static const _refresh = 'refresh-1';

  /// Whether the QR code was scanned and approved in Smart Life.
  bool approved = false;

  /// When set, sealed requests are refused with this message.
  String? refuse;

  final badRequests = <String>[];
  final signedOut = <Object?>[];
  var asked = 0;

  List<Map<String, Object?>> devices = [
    {
      'id': 'bf1234567890abcdefghij',
      'name': 'Kettle',
      'local_key': 'abcdefghijklmnop',
      'sub': false,
    },
    {
      'id': 'bf00000000000000sensor',
      'name': 'Door sensor',
      'local_key': 'ponmlkjihgfedcba',
      'sub': true,
    },
    {'id': 'nokey', 'name': 'No key'},
  ];

  Future<Map<String, dynamic>> send(
    String method,
    Uri uri, {
    Map<String, String> headers = const {},
    Object? body,
  }) async {
    asked++;
    const login = '/v1.0/m/life/home-assistant/qrcode/tokens';
    if (uri.path == login) {
      if (uri.queryParameters['usercode'] != userCode) {
        return {'success': false, 'code': 'E0001', 'msg': 'user code'};
      }
      return {
        'success': true,
        'result': {'qrcode': 'tok'},
      };
    }
    if (uri.path.startsWith('$login/')) {
      if (!approved) return {'success': false, 'code': 'pending'};
      return {
        'success': true,
        't': 1763618400000,
        'result': {
          'endpoint': 'https://apigw.tuyaeu.com',
          'access_token': 'access-1',
          'refresh_token': _refresh,
          'terminal_id': 'terminal-1',
          'expire_time': 7200,
          'uid': 'uid-1',
        },
      };
    }

    // Everything else is sealed and signed.
    final sealer = TuyaShareSealer(headers['X-requestId'] ?? '', _refresh);
    final query = uri.queryParameters['encdata'] ?? '';
    final sealedBody = body is Map ? '${body['encdata'] ?? ''}' : '';
    final signed = Map.of(headers)..remove('X-sign');
    if (uri.host != 'apigw.tuyaeu.com' ||
        headers['X-token'] != 'access-1' ||
        headers['X-sign'] != sealer.sign(signed, query, sealedBody)) {
      badRequests.add('$method ${uri.path}');
      return {'success': false, 'code': '1004', 'msg': 'sign invalid'};
    }
    if (refuse != null) return {'success': false, 'msg': refuse};

    Object? unseal(String sealed) {
      if (sealed.isEmpty) return null;
      // A request carries the nonce and the sealed text as two base64 parts.
      final nonce = base64Decode(sealed.substring(0, 16));
      final rest = base64Decode(sealed.substring(16));
      return jsonDecode(sealer.open(base64Encode([...nonce, ...rest])));
    }

    Map<String, dynamic> answer(Object? result) => {
      'success': true,
      'result': () {
        final sealed = sealer.seal(jsonEncode(result), '123456789012');
        return base64Encode([
          ...base64Decode(sealed.substring(0, 16)),
          ...base64Decode(sealed.substring(16)),
        ]);
      }(),
    };

    switch (uri.path) {
      case '/v1.0/m/life/users/homes':
        return answer([
          {'ownerId': 12345, 'name': 'Home'},
        ]);
      case '/v1.0/m/life/ha/home/devices':
        final asked = unseal(query);
        if (asked is! Map || asked['homeId'] != '12345') {
          badRequests.add('devices of $asked');
          return answer(const <Object?>[]);
        }
        return answer(devices);
      case '/v1.0/m/token/terminal/expire':
        signedOut.add(unseal(sealedBody));
        return {'success': true};
    }
    badRequests.add('$method ${uri.path}');
    return {'success': false, 'msg': 'unknown path'};
  }
}
