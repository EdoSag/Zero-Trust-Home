import 'dart:convert';
import 'dart:typed_data';

/// The little of DER (the encoding of X.509 certificates) that Matter
/// certificates need: writing them, and walking a signing request.

Uint8List _tlv(int tag, List<int> content) {
  final b = BytesBuilder()..addByte(tag);
  final n = content.length;
  if (n < 0x80) {
    b.addByte(n);
  } else if (n < 0x100) {
    b
      ..addByte(0x81)
      ..addByte(n);
  } else {
    b
      ..addByte(0x82)
      ..addByte(n >> 8)
      ..addByte(n & 0xFF);
  }
  b.add(content);
  return b.toBytes();
}

Uint8List _join(Iterable<List<int>> parts) {
  final b = BytesBuilder();
  for (final p in parts) {
    b.add(p);
  }
  return b.toBytes();
}

Uint8List derSequence(Iterable<List<int>> parts) => _tlv(0x30, _join(parts));
Uint8List derSet(Iterable<List<int>> parts) => _tlv(0x31, _join(parts));
Uint8List derOctets(List<int> bytes) => _tlv(0x04, bytes);
Uint8List derBool(bool value) => _tlv(0x01, [value ? 0xFF : 0x00]);
Uint8List derUtf8(String text) => _tlv(0x0C, utf8.encode(text));

/// A bit string with no unused bits.
Uint8List derBits(List<int> bytes, {int unused = 0}) =>
    _tlv(0x03, [unused, ...bytes]);

/// `[n]`, explicit: wraps whole values.
Uint8List derExplicit(int n, List<int> content) => _tlv(0xA0 | n, content);

/// `[n]`, implicit and primitive: replaces the tag of a simple value.
Uint8List derImplicit(int n, List<int> content) => _tlv(0x80 | n, content);

/// A non-negative integer from its big-endian bytes.
Uint8List derInt(List<int> magnitude) {
  var start = 0;
  while (start < magnitude.length - 1 && magnitude[start] == 0) {
    start++;
  }
  final trimmed = magnitude.isEmpty ? const [0] : magnitude.sublist(start);
  return _tlv(0x02, [if (trimmed.first & 0x80 != 0) 0, ...trimmed]);
}

Uint8List derBigInt(BigInt value) => derInt(bigIntBytes(value));

/// An object identifier from its dotted form.
Uint8List derOid(String dotted) {
  final arcs = dotted.split('.').map(int.parse).toList();
  final out = <int>[arcs[0] * 40 + arcs[1]];
  for (final arc in arcs.skip(2)) {
    final groups = <int>[arc & 0x7F];
    for (var rest = arc >> 7; rest > 0; rest >>= 7) {
      groups.add(0x80 | (rest & 0x7F));
    }
    out.addAll(groups.reversed);
  }
  return _tlv(0x06, out);
}

/// A time: UTCTime up to 2049, GeneralizedTime after, as X.509 asks.
Uint8List derTime(DateTime time) {
  final t = time.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  final rest =
      '${two(t.month)}${two(t.day)}${two(t.hour)}${two(t.minute)}'
      '${two(t.second)}Z';
  return t.year < 2050
      ? _tlv(0x17, ascii.encode('${two(t.year % 100)}$rest'))
      : _tlv(0x18, ascii.encode('${t.year.toString().padLeft(4, '0')}$rest'));
}

Uint8List bigIntBytes(BigInt value, {int? length}) {
  var hex = value.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  if (length != null) hex = hex.padLeft(length * 2, '0');
  return hexBytes(hex);
}

BigInt bytesBigInt(List<int> bytes) =>
    bytes.fold(BigInt.zero, (v, b) => (v << 8) | BigInt.from(b));

Uint8List hexBytes(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

String bytesHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// One value read from DER: its tag, its content, and all of its bytes.
class DerValue {
  DerValue._(this.tag, this.content, this.whole);
  final int tag;
  final Uint8List content;
  final Uint8List whole;

  /// The values inside a sequence, a set or an explicit tag.
  List<DerValue> get children => derReadAll(content);
}

class DerFormatException implements Exception {
  const DerFormatException(this.message);
  final String message;
  @override
  String toString() => 'DerFormatException: $message';
}

/// Reads every value in [data], one after the other.
List<DerValue> derReadAll(Uint8List data) {
  final out = <DerValue>[];
  var at = 0;
  while (at < data.length) {
    if (at + 2 > data.length) throw const DerFormatException('Cut short');
    final tag = data[at];
    var length = data[at + 1];
    var header = 2;
    if (length & 0x80 != 0) {
      final count = length & 0x7F;
      if (count == 0 || count > 3 || at + 2 + count > data.length) {
        throw const DerFormatException('Bad length');
      }
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | data[at + 2 + i];
      }
      header += count;
    }
    final end = at + header + length;
    if (end > data.length) throw const DerFormatException('Cut short');
    out.add(
      DerValue._(
        tag,
        Uint8List.sublistView(data, at + header, end),
        Uint8List.sublistView(data, at, end),
      ),
    );
    at = end;
  }
  return out;
}

/// The single value [data] holds.
DerValue derRead(Uint8List data) {
  final all = derReadAll(data);
  if (all.length != 1) throw const DerFormatException('Not one value');
  return all.single;
}
