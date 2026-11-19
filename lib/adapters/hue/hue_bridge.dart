import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// A home's Philips Hue Bridge: where it is, the key it gave this app when
/// its button was pressed, and the certificate it showed then. One per
/// home, saved as a vault item (kind `hue-bridge`), so the key is encrypted
/// on the phone and every phone of the account can use it.
@immutable
class HueBridge {
  const HueBridge({
    required this.homeId,
    required this.host,
    required this.key,
    this.certificate,
  });

  final String homeId;

  /// `192.168.1.20`, tidied up by [HueBridge.normalizeHost].
  final String host;

  /// The "application key" the bridge made for this app.
  final String key;

  /// SHA-256 of the certificate the bridge showed when it was paired, in
  /// hex. A bridge signs its own certificate, so no authority vouches for
  /// it; the app trusts the one it first saw and no other. Null when the
  /// bridge showed one any phone trusts.
  final String? certificate;

  String get id => itemId(homeId);

  static String itemId(String homeId) =>
      const Uuid().v5(Namespace.url.value, 'zerotrust-home:hue-bridge:$homeId');

  /// `https://192.168.1.20/` becomes `192.168.1.20`. Null when it can't be
  /// an address.
  static String? normalizeHost(String typed) {
    var text = typed.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'https://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z0-9.\-:\[\]]+$').hasMatch(uri.host)) return null;
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    return uri.hasPort && uri.port != 443 ? '$host:${uri.port}' : host;
  }

  Map<String, dynamic> toJson() => {
    'homeId': homeId,
    'host': host,
    'key': key,
    if (certificate != null) 'certificate': certificate,
  };

  static HueBridge fromJson(Map<String, dynamic> json) => HueBridge(
    homeId: json['homeId'] as String? ?? '',
    host: json['host'] as String? ?? '',
    key: json['key'] as String? ?? '',
    certificate: json['certificate'] as String?,
  );

  /// Everything a connection depends on.
  String get signature => '$host|$key|$certificate';
}
