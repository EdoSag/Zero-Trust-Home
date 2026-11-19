import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_home/adapters/tuya/tuya_codec.dart';

// Every expected value below was made with the open-source tinytuya
// library's own message packing (1.17.4), not with this app's code. If one
// fails, the app no longer speaks what real devices speak.

Uint8List hex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);

String toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List text(String s) => Uint8List.fromList(utf8.encode(s));

final key = text('0123456789abcdef');
final sessionKey = Uint8List.fromList([for (var i = 0; i < 16; i++) i]);
final localNonce = text('0123456789abcdef');
final remoteNonce = hex('6465666768696a6b6c6d6e6f70717273');
int fixedNow() => 1700000000;

const v33Query =
    '000055aa000000010000000a00000048e85dd832581fe4732bedd0efe0450ac930ae971ddb90f43af417c83d11e56ead89343b1bf77cf753bd8e6bb91a7c405ebe23f34440aefb47c4fa7fbe7027af01536215a50000aa55';
const v33Control =
    '000055aa000000020000000700000057332e33000000000000000000000000f36f3bf3e082b0e0638499f4fd3402c5012eea3a0f92a31c78edff31ddfdb02514289c9042f2aa08005786aab66fcc6d5c91b94d45d4e66e522e93cf8c4ab1fee69478870000aa55';
const v34Control =
    '000055aa000000030000000d000000743ca85ceaa9c73efc4536de356ff35c7aeafc4c153772ce79e3f9929b410130405df10c75a4175dc8a9bce334341ccbfea9558b9d79239322fd1f611e9e0125e175e0a71958934b6045aadfacb0d4187dc94e3074a60be5d78d62326a425ace3680645aebe61e69a3740b84ed20f9d3710000aa55';
const v35Control =
    '000066990000000000040000000d00000062303132333435363738396162889880b72079064fd981c8ca4d5edd5eb43bffa55260e9d1be948aac653577779635fbde4e9f113e044297ec51c4f702a43b83707cba6eaa0574302ba6521fd2baa35b37bde25f993b973f1b791e89e318e5afd12b7200009966';
const v35Status =
    '00006699000000000009000000080000005e303132333435363738396162bbb6b5b71357334fd981c8ca4d5edd25964b8db1047ff8d1a6d9d3f6253539618026b8cc449e0d2c5013d3a1519aed54a169ca2964a53ce805742d68fb0340dbb5ab50a5c3c92cb312e7c98acce81b4be12c00009966';
const v34SessionAnswer =
    '000055aa00000001000000040000006800000000938f3d8e1d412d55ebe9bf61ea1b0ea634a8706148aba7b9e47b4fd03c3428475216353fe75fa1cb7918233866ab9feb377222e061a924c591cd9c27ea163ed45f2c03ea41e5796c750ee645e2352f75e6d6a48eaef41d5e8b637d7d8d9adc2d0000aa55';
const v34SessionFinishPayload =
    '1b3940106e88c2074dd243e0928a320b71cc6856ddabdc15ee092a5cfa1ea535377222e061a924c591cd9c27ea163ed4';
const session34 = '9d30edf2f5b099256cec45a489054609';
const session35 = '361659af723c71d5575778e997cfb4e6';
const udp33 =
    '000055aa00000000000000130000009c00000000d09766676f3369eb10b5e9f132fd802a09797cd385303df9330482dd74a4f25d150931e65e45084a83b35b272a491c4ac95484d66641cf7820af3e9be42b9f095c907565b323a346d0de78c22f1fdaba1ae7c613c2cae004e54a474561367714379e7d68a02456269f4616388e2aa04ea5293c3042f2fea651a0076d6c53d48f49d7c04d4bd0e855432b819cbf4452f6c8f4ed3b0000aa55';
const udp35 =
    '0000669900000000000000000013000000aa303132333435363738396162042ce52c1986e9abb3bec8436999f733293fda25acbd8d0b2851e6e71da00fd51b5884a62c662b3511813b0416cfa1e5bcc151eb9b5761ea8438e2b6357302907753c72da02e4fbe9bc42f0a959426f5e375c9c1682c994b6d887b160dbe37fa10e7b0454c5306a58290a1052f09e68076317938fe2e1fd866fd3fb602b34b3f25f201e7e961100d556fbede49c9da8535b941586998109a0a0088b28fb900009966';

void main() {
  test('the broadcast key is the known one', () {
    expect(toHex(tuyaBroadcastKey), '6c1ec8e2bb9bb59ab50b0daf649b410a');
  });

  test('CRC32 matches the standard check value', () {
    expect(tuyaCrc32(ascii.encode('123456789')), 0xCBF43926);
  });

  group('3.3', () {
    test('query and control frames are byte for byte the reference', () {
      final codec = TuyaCodec(
        version: TuyaVersion.v33,
        deviceId: 'dev1',
        localKey: key,
        now: fixedNow,
      );
      expect(toHex(codec.query()), v33Query);
      expect(toHex(codec.control({'1': true})), v33Control);
    });

    test('a frame with a wrong checksum is refused', () {
      final broken = hex(v33Query);
      broken[20] ^= 1;
      expect(
        () => tuyaUnpack(broken, fromDevice: false),
        throwsA(isA<TuyaFormatException>()),
      );
    });
  });

  group('3.4', () {
    test('a control frame is byte for byte the reference', () {
      final plain = [
        ...TuyaVersion.v34.header,
        ...utf8.encode(
          '{"protocol":5,"t":1700000000,"data":{"dps":{"1":true}}}',
        ),
      ];
      final frame = tuyaPack55aa(
        sequence: 3,
        command: TuyaCommand.controlNew,
        payload: tuyaEcbEncrypt(sessionKey, plain),
        hmacKey: sessionKey,
      );
      expect(toHex(frame), v34Control);
    });

    test('the session key exchange matches the reference', () {
      final codec = TuyaCodec(
        version: TuyaVersion.v34,
        deviceId: 'dev1',
        localKey: key,
        now: fixedNow,
      );
      final start = codec.sessionStart(nonce: localNonce);
      final sent = tuyaUnpack(start, key: key, hmac: true, fromDevice: false);
      expect(sent.command, TuyaCommand.sessionStart);
      expect(tuyaEcbDecrypt(key, sent.payload), localNonce);

      final finish = codec.sessionFinish(hex(v34SessionAnswer));
      final done = tuyaUnpack(finish, key: key, hmac: true, fromDevice: false);
      expect(done.command, TuyaCommand.sessionFinish);
      expect(toHex(done.payload), v34SessionFinishPayload);

      // What comes next is sealed with the reference session key.
      final next = codec.control({'1': true});
      final opened = tuyaUnpack(
        next,
        key: hex(session34),
        hmac: true,
        fromDevice: false,
      );
      final plain = tuyaEcbDecrypt(hex(session34), opened.payload);
      expect(ascii.decode(plain.sublist(0, 3)), '3.4');
      expect(tuyaDps(tuyaJson(plain)), {'1': true});
    });

    test('a device with another local key is refused', () {
      final codec = TuyaCodec(
        version: TuyaVersion.v34,
        deviceId: 'dev1',
        localKey: key,
      )..sessionStart(nonce: text('another nonce 16'));
      expect(
        () => codec.sessionFinish(hex(v34SessionAnswer)),
        throwsA(isA<TuyaFormatException>()),
      );
    });
  });

  group('3.5', () {
    final iv = text('0123456789ab');
    final control = [
      ...TuyaVersion.v35.header,
      ...utf8.encode('{"protocol":5,"t":1700000000,"data":{"dps":{"1":true}}}'),
    ];

    test('a control frame is byte for byte the reference', () {
      final frame = tuyaPack6699(
        sequence: 4,
        command: TuyaCommand.controlNew,
        payload: control,
        key: sessionKey,
        iv: iv,
      );
      expect(toHex(frame), v35Control);
    });

    test('a frame from a device opens, return code apart', () {
      final frame = tuyaUnpack(hex(v35Status), key: sessionKey);
      expect(frame.command, TuyaCommand.status);
      expect(frame.sequence, 9);
      expect(frame.returnCode, 0);
      expect(tuyaDps(tuyaJson(frame.payload)), {'1': false});
    });

    test('a frame sealed with another key is refused', () {
      expect(
        () => tuyaUnpack(hex(v35Status), key: key),
        throwsA(isA<TuyaFormatException>()),
      );
    });

    test('the session key matches the reference', () {
      final mixed = Uint8List.fromList([
        for (var i = 0; i < 16; i++) localNonce[i] ^ remoteNonce[i],
      ]);
      expect(toHex(tuyaEcbEncrypt(key, mixed, pad: false)), session34);
      expect(
        toHex(
          tuyaGcmEncrypt(key, localNonce.sublist(0, 12), mixed).sublist(0, 16),
        ),
        session35,
      );
    });
  });

  group('discovery', () {
    test('a 3.3 announcement is read', () {
      final a = tuyaParseAnnouncement(hex(udp33))!;
      expect(a.deviceId, 'bf1234567890abcdefghij');
      expect(a.ip, '192.168.1.50');
      expect(a.version, TuyaVersion.v33);
      expect(a.productKey, 'keyabc');
    });

    test('a 3.5 announcement is read', () {
      final a = tuyaParseAnnouncement(hex(udp35))!;
      expect(a.ip, '192.168.1.50');
      expect(a.version, TuyaVersion.v35);
    });

    test('anything else is ignored', () {
      expect(tuyaParseAnnouncement(Uint8List(0)), isNull);
      expect(tuyaParseAnnouncement(text('hello there, not Tuya')), isNull);
      final broken = hex(udp35)..[40] ^= 1;
      expect(tuyaParseAnnouncement(broken), isNull);
    });

    test('the request for 3.5 devices opens with the broadcast key', () {
      final frame = tuyaUnpack(
        tuyaInfoRequest('192.168.1.7'),
        key: tuyaBroadcastKey,
        fromDevice: false,
      );
      expect(frame.command, TuyaCommand.requestInfo);
      expect(tuyaJson(frame.payload), {'from': 'app', 'ip': '192.168.1.7'});
    });
  });

  group('frame reader', () {
    test('frames split across packets and glued together are separated', () {
      final a = hex(v33Query), b = hex(v35Status);
      final stream = [...a, ...b];
      final reader = TuyaFrameReader();
      final frames = <Uint8List>[
        ...reader.add(stream.sublist(0, 10)),
        ...reader.add(stream.sublist(10, a.length + 7)),
        ...reader.add(stream.sublist(a.length + 7)),
      ];
      expect(frames.map(toHex), [v33Query, v35Status]);
    });

    test('noise before a frame is skipped', () {
      final reader = TuyaFrameReader();
      final frames = reader.add([1, 2, 3, 0, 9, ...hex(v33Query)]);
      expect(frames.map(toHex), [v33Query]);
    });
  });

  test('a local key is 16 characters', () {
    expect(tuyaParseLocalKey(' 0123456789abcdef '), isNotNull);
    expect(tuyaParseLocalKey('short'), isNull);
    expect(tuyaParseLocalKey('0123456789abcdefg'), isNull);
  });

  test('versions the app can and cannot talk to', () {
    expect(TuyaVersion.parse('3.2'), TuyaVersion.v33);
    expect(TuyaVersion.parse('3.4'), TuyaVersion.v34);
    expect(TuyaVersion.parse('3.1'), isNull);
    expect(TuyaVersion.parse(null), isNull);
  });
}
