import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_home/adapters/matter/der.dart';
import 'package:zerotrust_home/adapters/matter/matter_tlv.dart';

Object? _read(String hex) => matterTlvRead(hexBytes(hex.replaceAll(' ', '')));

void main() {
  // Encodings from the Matter specification, appendix A.12.
  test('simple values', () {
    expect(_read('08'), false);
    expect(_read('09'), true);
    expect(_read('00 2a'), 42);
    expect(_read('00 ef'), -17);
    expect(_read('04 2a'), 42);
    expect(_read('01 2a 00'), 42);
    expect(_read('02 f0 67 fd ff'), -170000);
    expect(_read('03 ff ff ff ff ff ff ff 7f'), 9223372036854775807);
    expect(_read('0c 06 48 65 6c 6c 6f 21'), 'Hello!');
    expect(_read('10 05 00 01 02 03 04'), Uint8List.fromList([0, 1, 2, 3, 4]));
    expect(_read('14'), isNull);
    expect(_read('0a 00 00 8c 41'), 17.5);
    expect(_read('0b 00 00 00 00 00 80 31 40'), 17.5);
  });

  test('structures, arrays and lists', () {
    expect(_read('15 18'), <int, Object?>{});
    expect(_read('16 18'), <Object?>[]);
    // {0 = 42, 1 = -17}
    expect(_read('15 20 00 2a 20 01 ef 18'), {0: 42, 1: -17});
    // [0, 1, 2, 3, 4]
    expect(_read('16 00 00 00 01 00 02 00 03 00 04 18'), [0, 1, 2, 3, 4]);
    // An array of structures, as a device lists its device types.
    expect(_read('16 15 25 00 0a 01 24 01 03 18 15 24 00 13 24 01 01 18 18'), [
      {0: 0x010A, 1: 3},
      {0: 0x13, 1: 1},
    ]);
    // A tagged value: the tag is the caller's business.
    expect(_read('24 01 2a'), 42);
    expect(_read('c4 f1 ff 00 00 01 00 2a'), 42);
    expect(_read('e4 f1 ff 00 00 01 00 00 00 2a'), 42);
  });

  test('damaged data is refused', () {
    for (final hex in ['', '15 20 00', '0c 06 48', '1f', '16 00']) {
      expect(() => _read(hex), throwsA(isA<MatterTlvException>()), reason: hex);
    }
  });

  test('command fields are written as the device expects', () {
    expect(bytesHex(matterTlvStruct()), '1518');
    // MoveToLevelWithOnOff: level 128, no transition time, no options.
    expect(
      bytesHex(
        matterTlvStruct(const [
          MatterTlvUint(0, 128),
          MatterTlvNull(1),
          MatterTlvUint(2, 0),
          MatterTlvUint(3, 0),
        ]),
      ),
      '15240080340124020024030018',
    );
    expect(
      bytesHex(
        matterTlvStruct(const [MatterTlvUint(0, 300), MatterTlvBool(1, true)]),
      ),
      '1525002c01290118',
    );
    // What is written reads back.
    expect(
      matterTlvRead(
        matterTlvStruct(const [
          MatterTlvUint(0, 70000),
          MatterTlvBool(1, false),
          MatterTlvNull(2),
        ]),
      ),
      {0: 70000, 1: false, 2: null},
    );
  });
}
