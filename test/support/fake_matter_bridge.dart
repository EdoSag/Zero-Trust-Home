import 'dart:async';
import 'dart:typed_data';

import 'package:zerotrust_home/adapters/matter/matter_adapter.dart';
import 'package:zerotrust_home/adapters/matter/matter_bridge.dart';
import 'package:zerotrust_home/adapters/matter/matter_fabric.dart';
import 'package:zerotrust_home/adapters/matter/matter_tlv.dart';

/// One part of a fake device: its device type and whether it dims.
class FakePart {
  FakePart({this.deviceType = 0x010A, this.dims = false});
  final int deviceType;
  final bool dims;
  bool on = false;
  int level = 254;
}

/// The Matter library without a phone or a device: a device with [parts]
/// waits in pairing mode under [code], and answers the way a real one
/// does once it has joined.
class FakeMatterBridge implements MatterBridge {
  FakeMatterBridge({this.code = '34970112332', Map<int, FakePart>? parts})
    : parts = parts ?? {1: FakePart()};

  final String code;
  final Map<int, FakePart> parts;
  final phone = matterNewKey();

  MatterFailure? failure;
  bool silent = false;

  /// The device joins, and then can't be read.
  bool unreadable = false;
  Completer<void>? holdPairing;
  bool ignoresCancel = false;

  /// Fabric ids, in the order they were started.
  final started = <String>[];
  final certificates = <Uint8List>[];
  final adminSubjects = <String>[];

  /// Node ids that joined, with the certificate each was given.
  final joined = <String, Uint8List>{};
  final removed = <String>[];
  final invoked = <(String, int, int, int, Object?)>[];
  var cancelled = 0;
  var phoneKeys = 0;

  Future<Uint8List> Function(Uint8List csr)? _issue;
  final _subscriptions = <String, List<StreamController<MatterEvent>>>{};

  void _check() {
    if (failure != null) throw MatterException(failure!, 'fake');
  }

  @override
  Future<Uint8List> phoneKey(String fabricId) async {
    _check();
    phoneKeys++;
    return phone.publicKey;
  }

  @override
  Future<void> start({
    required String fabricId,
    required Uint8List rootCert,
    required Uint8List certificate,
    required Uint8List ipk,
    required String adminSubject,
    required Future<Uint8List> Function(Uint8List csr) issue,
  }) async {
    _check();
    // As the real library: starting a fabric ends what ran on the other.
    for (final list in _subscriptions.values) {
      for (final c in list.toList()) {
        unawaited(c.close());
      }
    }
    _subscriptions.clear();
    started.add(fabricId);
    certificates.add(certificate);
    adminSubjects.add(adminSubject);
    _issue = issue;
  }

  @override
  Future<void> pair({required String nodeId, required String code}) async {
    _check();
    await holdPairing?.future;
    if (cancelled > 0 && !ignoresCancel) {
      throw const MatterException(MatterFailure.failed, 'Cancelled');
    }
    if (code != this.code) {
      throw const MatterException(MatterFailure.unreachable, 'not found');
    }
    final key = matterNewKey();
    joined[nodeId] = await _issue!(
      matterBuildCsr(key.privateKey, key.publicKey),
    );
  }

  @override
  Future<void> cancelPair() async => cancelled++;

  List<MatterAttribute> _values(List<MatterPath> paths) => [
    for (final path in paths)
      for (final MapEntry(key: endpoint, value: part) in parts.entries)
        if (path.endpoint == null || path.endpoint == endpoint)
          ?switch ((path.cluster, path.attribute)) {
            (MatterIds.descriptor, 0) => MatterAttribute(
              endpoint,
              path.cluster,
              0,
              [
                {0: part.deviceType, 1: 1},
              ],
            ),
            (MatterIds.descriptor, 1) =>
              MatterAttribute(endpoint, path.cluster, 1, [
                MatterIds.descriptor,
                MatterIds.onOff,
                if (part.dims) MatterIds.levelControl,
              ]),
            (MatterIds.onOff, 0) => MatterAttribute(
              endpoint,
              path.cluster,
              0,
              part.on,
            ),
            (MatterIds.levelControl, 0) when part.dims => MatterAttribute(
              endpoint,
              path.cluster,
              0,
              part.level,
            ),
            _ => null,
          },
  ];

  @override
  Future<List<MatterAttribute>> read(
    String nodeId,
    List<MatterPath> paths,
  ) async {
    _check();
    if (silent || unreadable || !joined.containsKey(nodeId)) {
      throw const MatterException(MatterFailure.unreachable);
    }
    return _values(paths);
  }

  static const _all = [
    MatterPath(null, MatterIds.onOff, 0),
    MatterPath(null, MatterIds.levelControl, 0),
  ];

  @override
  Stream<MatterEvent> subscribe(String nodeId, List<MatterPath> paths) {
    late final StreamController<MatterEvent> controller;
    controller = StreamController<MatterEvent>(
      onListen: () {
        if (failure != null || silent || !joined.containsKey(nodeId)) {
          controller.addError(const MatterException(MatterFailure.unreachable));
          unawaited(controller.close());
          return;
        }
        _subscriptions.putIfAbsent(nodeId, () => []).add(controller);
        controller.add(MatterReport(_values(paths)));
      },
      onCancel: () => _subscriptions[nodeId]?.remove(controller),
    );
    return controller.stream;
  }

  int subscribers(String nodeId) => _subscriptions[nodeId]?.length ?? 0;

  /// The device says what it is now, as after a change.
  void report(String nodeId) {
    for (final c in _subscriptions[nodeId] ?? const []) {
      c.add(MatterReport(_values(_all)));
    }
  }

  void reachable(String nodeId, bool reachable) {
    for (final c in _subscriptions[nodeId] ?? const []) {
      c.add(MatterReachable(reachable));
    }
  }

  @override
  Future<void> invoke(
    String nodeId, {
    required int endpoint,
    required int cluster,
    required int command,
    required Uint8List fields,
  }) async {
    _check();
    if (silent || !joined.containsKey(nodeId)) {
      throw const MatterException(MatterFailure.unreachable);
    }
    final values = matterTlvRead(fields);
    invoked.add((nodeId, endpoint, cluster, command, values));
    final part = parts[endpoint]!;
    if (cluster == MatterIds.onOff) part.on = command == 1;
    if (cluster == MatterIds.levelControl && command == 4) {
      part.level = (values as Map)[0] as int;
      part.on = true;
    }
    report(nodeId);
  }

  @override
  Future<void> remove(String nodeId) async {
    _check();
    if (silent) throw const MatterException(MatterFailure.unreachable);
    removed.add(nodeId);
    joined.remove(nodeId);
  }
}
