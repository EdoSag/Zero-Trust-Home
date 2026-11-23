import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

enum HueFailure {
  /// Nothing answered at the address.
  unreachable,

  /// The bridge wants its button pressed first.
  pressButton,

  /// The bridge no longer accepts this app's key.
  badKey,

  /// Something answered, but it isn't a Hue Bridge.
  notHue,

  /// What answers isn't the bridge that was paired: its certificate is a
  /// different one.
  changed,

  /// The bridge refused the request.
  failed,
}

class HueException implements Exception {
  const HueException(this.failure, [this.detail = '']);
  final HueFailure failure;
  final String detail;
  @override
  String toString() => 'HueException(${failure.name}: $detail)';
}

/// One bridge's local API (CLIP v2, over HTTPS on the home network). The
/// real one is [HttpHueLink]; tests give their own.
abstract class HueLink {
  /// Sends a request and returns the decoded JSON answer. Throws
  /// [HueException].
  Future<Object?> request(String method, String path, [Object? body]);

  /// Every change the bridge reports (one resource's changed fields each),
  /// until the connection closes. Errors are [HueException].
  Stream<Map<String, dynamic>> events();

  /// SHA-256 (hex) of the certificate the bridge showed, once it showed
  /// one.
  String? get seenCertificate;

  void close();
}

/// Opens a link to the bridge at [host]. With [pin], only a bridge showing
/// that certificate is talked to.
typedef HueConnect = HueLink Function(String host, {String? key, String? pin});

HueLink connectHueHttp(String host, {String? key, String? pin}) =>
    HttpHueLink(host, key: key, pin: pin);

class HttpHueLink implements HueLink {
  HttpHueLink(this.host, {this.key, this.pin}) {
    _http
      ..connectionTimeout = const Duration(seconds: 6)
      // The client trusts no authority, so this runs for every certificate,
      // before anything (the key included) is sent: a server with a
      // publicly trusted certificate for the bridge's name is held to the
      // pin too, and pairing always sees the certificate to pin.
      ..badCertificateCallback = (certificate, _, _) {
        final seen = _hex(
          SHA256Digest().process(Uint8List.fromList(certificate.der)),
        );
        seenCertificate = seen;
        return pin == null || pin == seen;
      };
  }

  final String host;
  final String? key;
  final String? pin;
  final _http = HttpClient(context: SecurityContext(withTrustedRoots: false));

  @override
  String? seenCertificate;

  static String _hex(List<int> bytes) =>
      [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

  HueException _failure(Object error) {
    if (error is HueException) return error;
    final seen = seenCertificate;
    if (error is HandshakeException && pin != null && seen != null) {
      if (seen != pin) return const HueException(HueFailure.changed);
    }
    return HueException(HueFailure.unreachable, '$error');
  }

  Future<HttpClientResponse> _open(
    String method,
    String path, {
    Object? body,
    String? accept,
  }) async {
    final request = await _http
        .openUrl(method, Uri.parse('https://$host$path'))
        .timeout(const Duration(seconds: 8));
    if (key != null) request.headers.set('hue-application-key', key!);
    if (accept != null) request.headers.set(HttpHeaders.acceptHeader, accept);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(body)));
    }
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode == 401 || response.statusCode == 403) {
      response.drain<void>().ignore();
      throw const HueException(HueFailure.badKey);
    }
    return response;
  }

  @override
  Future<Object?> request(String method, String path, [Object? body]) async {
    try {
      final response = await _open(method, path, body: body);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      final Object? json;
      try {
        json = jsonDecode(text);
      } on FormatException {
        throw const HueException(HueFailure.notHue);
      }
      if (response.statusCode >= 400) {
        throw HueException(
          response.statusCode == 404 ? HueFailure.notHue : HueFailure.failed,
          hueErrorText(json) ?? 'HTTP ${response.statusCode}',
        );
      }
      return json;
    } on Object catch (e) {
      throw _failure(e);
    }
  }

  @override
  Stream<Map<String, dynamic>> events() async* {
    final HttpClientResponse response;
    try {
      response = await _open(
        'GET',
        '/eventstream/clip/v2',
        accept: 'text/event-stream',
      );
      if (response.statusCode >= 400) {
        response.drain<void>().ignore();
        throw HueException(HueFailure.failed, 'HTTP ${response.statusCode}');
      }
    } on Object catch (e) {
      throw _failure(e);
    }
    final lines = response
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      yield* Stream.fromIterable(hueEventChanges(line.substring(5)));
    }
  }

  @override
  void close() => _http.close(force: true);
}

/// The description of the first error in a CLIP v2 answer, if it has one.
String? hueErrorText(Object? json) {
  if (json is! Map) return null;
  final errors = json['errors'];
  if (errors is! List || errors.isEmpty) return null;
  final first = errors.first;
  return first is Map ? first['description'] as String? : null;
}

/// Set (to true) on a change that says the resource was deleted.
const hueDeleted = 'zt_deleted';

/// The resources changed in one `data:` line of the bridge's event stream.
/// A deleted one comes with [hueDeleted] set.
List<Map<String, dynamic>> hueEventChanges(String data) {
  final Object? json;
  try {
    json = jsonDecode(data);
  } on FormatException {
    return const [];
  }
  return [
    for (final event in json is List ? json : const <Object?>[])
      if (event is Map &&
          const {'update', 'add', 'delete'}.contains(event['type']))
        for (final item in event['data'] as List? ?? const <Object?>[])
          if (item is Map)
            {
              ...Map<String, dynamic>.from(item),
              if (event['type'] == 'delete') hueDeleted: true,
            },
  ];
}
