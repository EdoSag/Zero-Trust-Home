import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'tuya_codec.dart';

/// Why talking to a device failed.
enum TuyaFailure {
  /// No answer at that address: off, on another network, or moved.
  unreachable,

  /// It answered, but not to this local key (or protocol version).
  keyRejected,
}

class TuyaException implements Exception {
  const TuyaException(this.failure, [this.detail = '']);
  final TuyaFailure failure;
  final String detail;
  @override
  String toString() => 'TuyaException(${failure.name}) $detail';
}

/// Opens the connection to a device. Tests pass their own.
typedef TuyaConnector = Future<Socket> Function(String host, int port);

Future<Socket> _connect(String host, int port) =>
    Socket.connect(host, port, timeout: const Duration(seconds: 5));

/// One open connection to one Tuya device on the home network: agrees the
/// session key (3.4, 3.5), then queries, sets and listens. Requests go one
/// at a time. Once [done] completes the link is finished; open a new one.
class TuyaLink {
  TuyaLink._(this._socket, this._codec, this._timeout);

  static const port = 6668;

  final Socket _socket;
  final TuyaCodec _codec;
  final Duration _timeout;
  final _reader = TuyaFrameReader();
  final _changes = StreamController<Map<String, dynamic>>.broadcast();
  final _done = Completer<void>();
  final _waiting = <_Pending>[];
  Future<void> _queue = Future.value();
  var _closed = false;

  /// Data points the device reports, as they change (and every answer to
  /// a [query]). Keys are data point numbers: `{'1': true}`.
  Stream<Map<String, dynamic>> get changes => _changes.stream;

  /// Completes when the connection is gone, however it ended.
  Future<void> get done => _done.future;
  bool get isOpen => !_closed;

  /// Connects and, for 3.4 and 3.5, agrees the session key. Throws
  /// [TuyaException]: unreachable when nothing answers, keyRejected when
  /// the device doesn't accept [localKey].
  static Future<TuyaLink> open({
    required String host,
    required String deviceId,
    required Uint8List localKey,
    required TuyaVersion version,
    int port = TuyaLink.port,
    Duration timeout = const Duration(seconds: 5),
    TuyaConnector? connector,
  }) async {
    final Socket socket;
    try {
      socket = await (connector ?? _connect)(host, port).timeout(timeout);
    } on Object catch (e) {
      throw TuyaException(TuyaFailure.unreachable, '$e');
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    final link = TuyaLink._(
      socket,
      TuyaCodec(version: version, deviceId: deviceId, localKey: localKey),
      timeout,
    );
    link._listen();
    if (version.negotiates) {
      try {
        await link._negotiate();
      } on Object {
        await link.close();
        rethrow;
      }
    }
    return link;
  }

  void _listen() {
    _socket.listen(
      (bytes) {
        final List<Uint8List> frames;
        try {
          frames = _reader.add(bytes);
        } on TuyaFormatException catch (e) {
          _fail(TuyaException(TuyaFailure.keyRejected, e.message));
          return;
        }
        for (final frame in frames) {
          _onFrame(frame);
        }
      },
      onError: (Object e) =>
          _fail(TuyaException(TuyaFailure.unreachable, '$e')),
      onDone: () => _fail(const TuyaException(TuyaFailure.unreachable)),
      cancelOnError: true,
    );
  }

  void _onFrame(Uint8List frame) {
    // The session answer is opened by the one waiting for it.
    final raw = _waiting.where((p) => p.raw).firstOrNull;
    if (raw != null) {
      _waiting.remove(raw);
      raw.completer.complete(_Answer(raw: frame));
      return;
    }
    final ({int command, Map<String, dynamic>? json, bool refused}) message;
    try {
      message = _codec.read(frame);
    } on TuyaFormatException catch (e) {
      // Sealed with another key: this local key isn't the device's.
      _fail(TuyaException(TuyaFailure.keyRejected, e.message));
      return;
    }
    final dps = tuyaDps(message.json);
    if (dps != null && dps.isNotEmpty && !_changes.isClosed) _changes.add(dps);
    final pending = _waiting
        .where((p) => p.command == message.command)
        .firstOrNull;
    if (pending != null) {
      _waiting.remove(pending);
      pending.completer.complete(_Answer(dps: dps, refused: message.refused));
    }
  }

  void _fail(TuyaException error) {
    if (_closed) return;
    _closed = true;
    for (final p in _waiting) {
      if (!p.completer.isCompleted) p.completer.completeError(error);
    }
    _waiting.clear();
    _socket.destroy();
    unawaited(_changes.close());
    if (!_done.isCompleted) _done.complete();
  }

  /// Sends [frame] and waits for the device's answer with [command].
  Future<_Answer> _request(
    Uint8List Function() frame,
    int Function() command, {
    bool raw = false,
    TuyaFailure onSilence = TuyaFailure.keyRejected,
  }) {
    final result = _queue.then((_) async {
      if (_closed) throw const TuyaException(TuyaFailure.unreachable);
      final pending = _Pending(command(), raw);
      _waiting.add(pending);
      try {
        _socket.add(frame());
        return await pending.completer.future.timeout(_timeout);
      } on TimeoutException {
        // Connected but silent: a device ignores what it can't decrypt.
        final error = TuyaException(onSilence, 'No answer');
        _fail(error);
        throw error;
      } finally {
        _waiting.remove(pending);
      }
    });
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _negotiate() async {
    final answer = await _request(
      _codec.sessionStart,
      () => TuyaCommand.sessionResponse,
      raw: true,
    );
    try {
      _socket.add(_codec.sessionFinish(answer.raw!));
    } on TuyaFormatException catch (e) {
      throw TuyaException(TuyaFailure.keyRejected, e.message);
    }
  }

  /// Every data point of the device, also sent to [changes].
  Future<Map<String, dynamic>> query() async {
    var answer = await _request(_codec.query, () => _codec.queryCommand);
    if (answer.refused && !_codec.queryAsControl) {
      _codec.queryAsControl = true;
      answer = await _request(_codec.query, () => _codec.queryCommand);
    }
    return answer.dps ?? const {};
  }

  /// Sets data points and waits for the device to acknowledge.
  Future<void> set(Map<String, dynamic> dps) async {
    await _request(() => _codec.control(dps), () => _codec.controlCommand);
  }

  /// Fails when the device stopped answering.
  Future<void> heartbeat() async {
    await _request(
      _codec.heartbeat,
      () => TuyaCommand.heartbeat,
      onSilence: TuyaFailure.unreachable,
    );
  }

  /// Asks for fresh readings of [dpIds]; they arrive on [changes]. Not
  /// every device answers this, so it doesn't wait.
  void refresh(List<int> dpIds) {
    _queue = _queue.then((_) {
      if (!_closed) _socket.add(_codec.refresh(dpIds));
    });
  }

  Future<void> close() async {
    _fail(const TuyaException(TuyaFailure.unreachable, 'Closed'));
  }
}

class _Pending {
  _Pending(this.command, this.raw);
  final int command;
  final bool raw;
  final completer = Completer<_Answer>();
}

class _Answer {
  const _Answer({this.dps, this.raw, this.refused = false});
  final Map<String, dynamic>? dps;
  final Uint8List? raw;
  final bool refused;
}
