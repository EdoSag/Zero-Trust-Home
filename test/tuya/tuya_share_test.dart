import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_home/adapters/tuya/tuya_share.dart';

import '../support/fake_tuya_cloud.dart';

void main() {
  // Values made with Tuya's own library (tuya-device-sharing-sdk 0.2.15).
  group('sealer matches Tuya\'s library', () {
    final sealer = TuyaShareSealer(
      '6f1c1f0e-8f5e-4c53-9a37-0d0c9d0b7a11',
      'refreshTOKEN123',
    );
    const sealed =
        'QUJDREVGR0hKS01Os2mKbEUUhbCbRfgOsJf4Now4t63EwVG3mlU0Y5Rn5It2IA==';

    test('keys', () {
      expect(sealer.hashKey, '3512ef67545a62e3f8f550c4027185ed');
      expect(sealer.secret, '2ed339a81dddb400');
    });

    test('seals a query', () {
      expect(sealer.seal('{"homeId":"12345"}', 'ABCDEFGHJKMN'), sealed);
    });

    test('signs', () {
      expect(
        sealer.sign(
          {
            'X-appKey': 'CLIENT',
            'X-requestId': '6f1c1f0e-8f5e-4c53-9a37-0d0c9d0b7a11',
            'X-sid': '',
            'X-time': '1763618400000',
            'X-token': 'ACCESS',
          },
          sealed,
          '',
        ),
        'c7b9a478e0b147eb0c12806e906eeb0e70f721b0eb681c0b3544b2f282c31c66',
      );
    });

    test('opens an answer', () {
      expect(
        sealer.open('MTIzNDU2Nzg5MDEyas81lkQg+iAXxn0QpbDIQoftaKK0taO/5CuEDmmJ'),
        '[{"id":"abc"}]',
      );
    });

    test('an answer that was tampered with is refused', () {
      expect(
        () => sealer.open(
          'MTIzNDU2Nzg5MDEyas81lkQg+iAXxn0QpbDIQoftaKK0taO/5CuEDmmK',
        ),
        throwsA(isA<TuyaShareException>()),
      );
    });
  });

  group('link', () {
    late FakeTuyaCloud cloud;
    late TuyaShare share;

    setUp(() {
      cloud = FakeTuyaCloud();
      share = TuyaShare(send: cloud.send, random: Random(1));
    });

    test('the QR code says what Smart Life expects', () {
      expect(TuyaShare.qrText('tok'), 'tuyaSmart--qrLogin?token=tok');
    });

    test('an unknown user code is told apart', () async {
      await expectLater(
        share.start('nope'),
        throwsA(
          isA<TuyaShareException>().having(
            (e) => e.failure,
            'failure',
            TuyaShareFailure.badUserCode,
          ),
        ),
      );
    });

    test('nothing until the code is approved, then the keys', () async {
      final token = await share.start(FakeTuyaCloud.userCode);
      expect(await share.check(token, FakeTuyaCloud.userCode), isNull);

      cloud.approved = true;
      final session = (await share.check(token, FakeTuyaCloud.userCode))!;
      final devices = await share.devices(session);
      expect(
        {for (final d in devices) d.deviceId: (d.name, d.localKey, d.sub)},
        {
          'bf1234567890abcdefghij': ('Kettle', 'abcdefghijklmnop', false),
          'bf00000000000000sensor': ('Door sensor', 'ponmlkjihgfedcba', true),
        },
      );
      // Every request was signed and sealed the way the cloud checks.
      expect(cloud.badRequests, isEmpty);

      await share.signOut(session);
      expect(cloud.signedOut, [
        {'accessToken': 'access-1', 'terminalId': 'terminal-1'},
      ]);
    });

    test('waiting ends when the code is approved', () async {
      final token = await share.start(FakeTuyaCloud.userCode);
      var asked = 0;
      final session = await share.wait(
        token,
        FakeTuyaCloud.userCode,
        every: Duration.zero,
        stopped: () {
          if (++asked == 3) cloud.approved = true;
          return false;
        },
      );
      expect(session?.accessToken, 'access-1');
    });

    test('waiting gives up after the time allowed', () async {
      var now = DateTime(2026, 11, 20);
      share = TuyaShare(
        send: cloud.send,
        now: () => now = now.add(const Duration(seconds: 50)),
      );
      await expectLater(
        share.wait('tok', FakeTuyaCloud.userCode, every: Duration.zero),
        throwsA(
          isA<TuyaShareException>().having(
            (e) => e.failure,
            'failure',
            TuyaShareFailure.expired,
          ),
        ),
      );
    });

    test('a refusal from the cloud carries its reason', () async {
      cloud.approved = true;
      final session = (await share.check('tok', FakeTuyaCloud.userCode))!;
      cloud.refuse = 'sign invalid';
      await expectLater(
        share.devices(session),
        throwsA(
          isA<TuyaShareException>()
              .having((e) => e.failure, 'failure', TuyaShareFailure.refused)
              .having((e) => e.detail, 'detail', 'sign invalid'),
        ),
      );
    });

    test('devices without a key are left out', () {
      expect(TuyaSharedDevice.from({'id': 'x', 'name': 'n'}), isNull);
      expect(TuyaSharedDevice.from(jsonDecode('[]')), isNull);
    });
  });
}
