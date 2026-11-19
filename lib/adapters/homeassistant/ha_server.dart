import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// A home's Home Assistant: where it is and the token that lets the app in.
/// One per home, saved as a vault item (kind `ha-server`), so the token is
/// encrypted on the phone and every phone of the account can use it.
@immutable
class HaServer {
  const HaServer({
    required this.homeId,
    required this.url,
    required this.token,
  });

  final String homeId;

  /// As the person typed it, tidied up by [HaServer.normalizeUrl]:
  /// `http://192.168.1.10:8123`.
  final String url;

  /// A long-lived access token from the person's Home Assistant profile.
  final String token;

  String get id => itemId(homeId);

  static String itemId(String homeId) =>
      const Uuid().v5(Namespace.url.value, 'zerotrust-home:ha-server:$homeId');

  /// The WebSocket address of the server's API.
  Uri get socketUri {
    final base = Uri.parse(url);
    final path = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '$path/api/websocket',
      query: null,
      fragment: null,
    );
  }

  /// `homeassistant.local` becomes `http://homeassistant.local:8123`; a
  /// full address is kept. Null when it can't be an address.
  static String? normalizeUrl(String typed) {
    var text = typed.trim();
    if (text.isEmpty) return null;
    final hasScheme = text.contains('://');
    if (!hasScheme) text = 'http://$text';
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.host.isEmpty ||
        !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }
    // Home Assistant's own port, unless the person gave one or a scheme
    // (a reverse proxy on 443 is reached as https://name).
    final port = !hasScheme && !uri.hasPort ? 8123 : null;
    final path = uri.path == '/' ? '' : uri.path;
    return uri
        .replace(port: port ?? (uri.hasPort ? uri.port : null), path: path)
        .removeFragment()
        .toString()
        .replaceAll(RegExp(r'\?$'), '');
  }

  Map<String, dynamic> toJson() => {
    'homeId': homeId,
    'url': url,
    'token': token,
  };

  static HaServer fromJson(Map<String, dynamic> json) => HaServer(
    homeId: json['homeId'] as String? ?? '',
    url: json['url'] as String? ?? '',
    token: json['token'] as String? ?? '',
  );

  /// Everything a connection depends on.
  String get signature => '$url|$token';
}
