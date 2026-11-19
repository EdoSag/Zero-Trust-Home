import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'matter_tlv.dart';

/// One attribute of a device: endpoint (a part of the device, like one
/// socket of a power strip), cluster (a feature, like on/off) and the
/// attribute within it. [endpoint] null means "every endpoint".
@immutable
class MatterPath {
  const MatterPath(this.endpoint, this.cluster, this.attribute);
  final int? endpoint;
  final int cluster;
  final int attribute;
}

/// An attribute's value as the device reported it (see [matterTlvRead]).
@immutable
class MatterAttribute {
  const MatterAttribute(
    this.endpoint,
    this.cluster,
    this.attribute,
    this.value,
  );
  final int endpoint;
  final int cluster;
  final int attribute;
  final Object? value;
}

/// What a subscription to a device tells.
sealed class MatterEvent {
  const MatterEvent();
}

/// Values, at first all of them and then each as it changes.
class MatterReport extends MatterEvent {
  const MatterReport(this.attributes);
  final List<MatterAttribute> attributes;
}

/// The device stopped answering (false) or answers again (true).
class MatterReachable extends MatterEvent {
  const MatterReachable(this.reachable);
  final bool reachable;
}

enum MatterFailure {
  /// This phone can't run the Matter library (not a 64-bit ARM phone).
  unsupported,

  /// Bluetooth is off, or the phone has none.
  bluetoothOff,

  /// The person didn't allow the app to use Bluetooth.
  bluetoothDenied,

  /// The device didn't answer, or wasn't found on the network.
  unreachable,

  /// The device or the library refused; [MatterException.detail] says how.
  failed,
}

class MatterException implements Exception {
  const MatterException(this.failure, [this.detail = '']);
  final MatterFailure failure;
  final String detail;
  @override
  String toString() => 'MatterException(${failure.name}) $detail';
}

/// The home's Wi-Fi, given to a new device so it can join it.
@immutable
class MatterWifi {
  const MatterWifi({required this.ssid, required this.password});
  final String ssid;
  final String password;
}

/// The Matter library, which is native code. Node and fabric ids are 16
/// hex digits. Tests use a fake.
abstract interface class MatterBridge {
  /// The public key (65 bytes) of this phone's own key for a fabric, made
  /// on first use. The private key never leaves the phone's key store.
  Future<Uint8List> phoneKey(String fabricId);

  /// Starts controlling one fabric as the node of [certificate], ending
  /// any other. [issue] is asked for a certificate for each device being
  /// added, from the signing request the device sent.
  Future<void> start({
    required String fabricId,
    required Uint8List rootCert,
    required Uint8List certificate,
    required Uint8List ipk,
    required String adminSubject,
    required Future<Uint8List> Function(Uint8List csr) issue,
  });

  /// Adds the device in pairing mode that [code] belongs to (a QR code's
  /// text or the typed code) to the fabric, as node [nodeId]. Without
  /// [wifi] the device must already be on the home network. With it, a
  /// new device is also looked for over Bluetooth and given the Wi-Fi.
  Future<void> pair({
    required String nodeId,
    required String code,
    MatterWifi? wifi,
  });

  /// Opens the camera to scan a QR code; its text, or null when the
  /// person went back.
  Future<String?> scanCode();

  /// Gives up a [pair] that is still running.
  Future<void> cancelPair();

  Future<List<MatterAttribute>> read(String nodeId, List<MatterPath> paths);

  /// Follows attributes until the stream is cancelled. An error means the
  /// device could not be reached at all; the stream then ends.
  Stream<MatterEvent> subscribe(String nodeId, List<MatterPath> paths);

  /// Sends a command with its [fields] (see [matterTlvStruct]).
  Future<void> invoke(
    String nodeId, {
    required int endpoint,
    required int cluster,
    required int command,
    required Uint8List fields,
  });

  /// Tells the device to leave the fabric.
  Future<void> remove(String nodeId);
}

/// The bridge to the Android side (`MatterPlugin.kt`).
class MatterChannelBridge implements MatterBridge {
  MatterChannelBridge([MethodChannel? channel])
    : _channel =
          channel ?? const MethodChannel('dev.sagron.zerotrusthome/matter') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  Future<Uint8List> Function(Uint8List csr)? _issue;
  final _subscriptions = <int, StreamController<MatterEvent>>{};
  var _nextSubscription = 1;

  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      throw const MatterException(MatterFailure.unsupported);
    } on PlatformException catch (e) {
      throw MatterException(switch (e.code) {
        'unsupported' => MatterFailure.unsupported,
        'unreachable' => MatterFailure.unreachable,
        'bluetoothOff' => MatterFailure.bluetoothOff,
        'bluetoothDenied' => MatterFailure.bluetoothDenied,
        _ => MatterFailure.failed,
      }, e.message ?? e.code);
    }
  }

  Future<Object?> _onCall(MethodCall call) async {
    final arguments = (call.arguments as Map?) ?? const {};
    switch (call.method) {
      case 'issueDevice':
        final issue = _issue;
        if (issue == null) throw StateError('No fabric started');
        return issue(arguments['csr'] as Uint8List);
      case 'report':
        _subscriptions[arguments['subscription']]?.add(
          MatterReport(_attributes(arguments['attributes'])),
        );
      case 'reachable':
        _subscriptions[arguments['subscription']]?.add(
          MatterReachable(arguments['reachable'] == true),
        );
      case 'subscriptionFailed':
        final controller = _subscriptions.remove(arguments['subscription']);
        controller?.addError(
          MatterException(
            MatterFailure.unreachable,
            '${arguments['message'] ?? ''}',
          ),
        );
        unawaited(controller?.close());
    }
    return null;
  }

  /// Rows of endpoint, cluster, attribute and the value's TLV bytes. A
  /// value that can't be read is skipped, not an error for the rest.
  static List<MatterAttribute> _attributes(Object? rows) => [
    for (final row in rows as List? ?? const [])
      if (row is List && row.length == 4 && row[3] is Uint8List)
        ?_attribute(row),
  ];

  static MatterAttribute? _attribute(List<Object?> row) {
    try {
      return MatterAttribute(
        (row[0] as num).toInt(),
        (row[1] as num).toInt(),
        (row[2] as num).toInt(),
        matterTlvRead(row[3] as Uint8List),
      );
    } on Object {
      return null;
    }
  }

  static List<List<int>> _paths(List<MatterPath> paths) => [
    for (final p in paths) [p.endpoint ?? -1, p.cluster, p.attribute],
  ];

  @override
  Future<Uint8List> phoneKey(String fabricId) async =>
      (await _call<Uint8List>('phoneKey', {'fabricId': fabricId}))!;

  @override
  Future<void> start({
    required String fabricId,
    required Uint8List rootCert,
    required Uint8List certificate,
    required Uint8List ipk,
    required String adminSubject,
    required Future<Uint8List> Function(Uint8List csr) issue,
  }) async {
    _issue = issue;
    await _call<void>('start', {
      'fabricId': fabricId,
      'rootCert': rootCert,
      'certificate': certificate,
      'ipk': ipk,
      'adminSubject': adminSubject,
    });
  }

  @override
  Future<void> pair({
    required String nodeId,
    required String code,
    MatterWifi? wifi,
  }) => _call<void>('pair', {
    'nodeId': nodeId,
    'code': code,
    if (wifi != null) 'ssid': wifi.ssid,
    if (wifi != null) 'password': wifi.password,
  });

  @override
  Future<String?> scanCode() => _call<String>('scanCode');

  @override
  Future<void> cancelPair() => _call<void>('cancelPair');

  @override
  Future<List<MatterAttribute>> read(
    String nodeId,
    List<MatterPath> paths,
  ) async => _attributes(
    await _call<List<Object?>>('read', {
      'nodeId': nodeId,
      'paths': _paths(paths),
    }),
  );

  @override
  Stream<MatterEvent> subscribe(String nodeId, List<MatterPath> paths) {
    final id = _nextSubscription++;
    late final StreamController<MatterEvent> controller;
    controller = StreamController<MatterEvent>(
      onListen: () async {
        _subscriptions[id] = controller;
        try {
          await _call<void>('subscribe', {
            'subscription': id,
            'nodeId': nodeId,
            'paths': _paths(paths),
          });
        } on Object catch (e, s) {
          if (_subscriptions.remove(id) != null) {
            controller.addError(e, s);
            unawaited(controller.close());
          }
        }
      },
      onCancel: () async {
        if (_subscriptions.remove(id) == null) return;
        try {
          await _call<void>('unsubscribe', {'subscription': id});
        } on Object {
          // Already gone with its controller.
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> invoke(
    String nodeId, {
    required int endpoint,
    required int cluster,
    required int command,
    required Uint8List fields,
  }) => _call<void>('invoke', {
    'nodeId': nodeId,
    'endpoint': endpoint,
    'cluster': cluster,
    'command': command,
    'fields': fields,
  });

  @override
  Future<void> remove(String nodeId) =>
      _call<void>('remove', {'nodeId': nodeId});
}
