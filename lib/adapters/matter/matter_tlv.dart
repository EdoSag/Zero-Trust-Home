import 'dart:convert';
import 'dart:typed_data';

/// Matter's own encoding of values ("TLV"): what a device reports and what
/// a command carries.
///
/// Read into plain Dart values: a structure is a `Map<int, Object?>` by
/// field number, an array or list is a `List<Object?>`, then `int`,
/// `double`, `bool`, `String`, `Uint8List` and `null`.
class MatterTlvException implements Exception {
  const MatterTlvException(this.message);
  final String message;
  @override
  String toString() => 'MatterTlvException: $message';
}

/// Reads the one value in [data] (its own tag is ignored).
Object? matterTlvRead(Uint8List data) {
  final reader = _Reader(data);
  final value = reader.element().value;
  return value;
}

class _Element {
  _Element(this.tag, this.value, {this.end = false});
  final int? tag;
  final Object? value;
  final bool end;
}

class _Reader {
  _Reader(this.data);
  final Uint8List data;
  var at = 0;

  int _take(int count) {
    if (at + count > data.length) throw const MatterTlvException('Cut short');
    var value = 0;
    for (var i = count - 1; i >= 0; i--) {
      value = (value << 8) | data[at + i];
    }
    at += count;
    return value;
  }

  Uint8List _bytes(int count) {
    if (count < 0 || at + count > data.length) {
      throw const MatterTlvException('Cut short');
    }
    final out = Uint8List.sublistView(data, at, at + count);
    at += count;
    return out;
  }

  _Element element() {
    final control = _take(1);
    final type = control & 0x1F;
    int? tag;
    switch (control >> 5) {
      case 0:
        break;
      case 1:
        tag = _take(1);
      case 2 || 4:
        tag = _take(2);
      case 3 || 5:
        tag = _take(4);
      case 6:
        _take(4);
        tag = _take(2);
      default:
        _take(4);
        tag = _take(4);
    }
    if (type == 0x18) return _Element(tag, null, end: true);
    return _Element(tag, _value(type));
  }

  Object? _value(int type) {
    switch (type) {
      case >= 0x00 && <= 0x03:
        final size = 1 << type;
        return _take(size).toSigned(8 * size);
      case >= 0x04 && <= 0x07:
        return _take(1 << (type - 4));
      case 0x08:
        return false;
      case 0x09:
        return true;
      case 0x0A:
        return ByteData.sublistView(_bytes(4)).getFloat32(0, Endian.little);
      case 0x0B:
        return ByteData.sublistView(_bytes(8)).getFloat64(0, Endian.little);
      case >= 0x0C && <= 0x0F:
        return utf8.decode(
          _bytes(_take(1 << (type - 0x0C))),
          allowMalformed: true,
        );
      case >= 0x10 && <= 0x13:
        return Uint8List.fromList(_bytes(_take(1 << (type - 0x10))));
      case 0x14:
        return null;
      case 0x15:
        final fields = <int, Object?>{};
        while (true) {
          final e = element();
          if (e.end) return fields;
          if (e.tag != null) fields[e.tag!] = e.value;
        }
      case 0x16 || 0x17:
        final items = <Object?>[];
        while (true) {
          final e = element();
          if (e.end) return items;
          items.add(e.value);
        }
      default:
        throw MatterTlvException('Unknown type $type');
    }
  }
}

/// A field of a command, for [matterTlvStruct].
sealed class MatterTlvField {
  const MatterTlvField(this.tag);
  final int tag;
}

/// An unsigned number, in the smallest size that holds it.
class MatterTlvUint extends MatterTlvField {
  const MatterTlvUint(super.tag, this.value);
  final int value;
}

class MatterTlvBool extends MatterTlvField {
  const MatterTlvBool(super.tag, this.value);
  final bool value;
}

class MatterTlvNull extends MatterTlvField {
  const MatterTlvNull(super.tag);
}

/// The fields of a command, as the structure a device expects. No fields
/// gives the empty structure that commands like On and Off take.
Uint8List matterTlvStruct([List<MatterTlvField> fields = const []]) {
  final b = BytesBuilder()..addByte(0x15);
  for (final field in fields) {
    // Context tag: the field's number within its command.
    switch (field) {
      case MatterTlvUint(:final value):
        final size = value < 0x100
            ? 0
            : value < 0x10000
            ? 1
            : value < 0x100000000
            ? 2
            : 3;
        b
          ..addByte(0x20 | (0x04 + size))
          ..addByte(field.tag);
        for (var i = 0; i < 1 << size; i++) {
          b.addByte((value >> (8 * i)) & 0xFF);
        }
      case MatterTlvBool(:final value):
        b
          ..addByte(0x20 | (value ? 0x09 : 0x08))
          ..addByte(field.tag);
      case MatterTlvNull():
        b
          ..addByte(0x20 | 0x14)
          ..addByte(field.tag);
    }
  }
  b.addByte(0x18);
  return b.toBytes();
}
