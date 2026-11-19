import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_home/adapters/matter/matter_setup_code.dart';

Matcher _fails(MatterSetupCodeProblem problem) => throwsA(
  isA<MatterSetupCodeException>().having((e) => e.problem, 'problem', problem),
);

void main() {
  group('QR code', () {
    test('the Matter SDK\'s test code', () {
      // connectedhomeip, src/setup_payload/tests/TestHelpers.h
      final code = MatterSetupCode.parse('MT:M5L90MP500K64J00000');
      expect(code.vendorId, 12);
      expect(code.productId, 1);
      expect(code.discriminator, 128);
      expect(code.shortDiscriminator, isFalse);
      expect(code.passcode, 2048);
      expect(code.bluetooth, isFalse);
      expect(code.onNetwork, isFalse);
      expect(code.fromQr, isTrue);
    });

    test('the code every Matter sample device ships with', () {
      final code = MatterSetupCode.parse(' mt:Y.K9042C00KA0648G00\n');
      expect(code.vendorId, 0xFFF1);
      expect(code.productId, 0x8000);
      expect(code.discriminator, 3840);
      expect(code.passcode, 20202021);
      expect(code.bluetooth, isTrue);
    });

    test('a sticker for several devices gives the first', () {
      final code = MatterSetupCode.parse(
        'MT:M5L90MP500K64J00000*M5L90U.D010K4J00000',
      );
      expect(code.passcode, 2048);
    });

    test('other QR codes are told apart', () {
      expect(MatterSetupCode.isQr('MT:M5L90MP500K64J00000'), isTrue);
      expect(MatterSetupCode.isQr('https://example.com'), isFalse);
      expect(MatterSetupCode.isQr('WIFI:S:home;;'), isFalse);
    });

    test('a damaged one is refused', () {
      expect(
        () => MatterSetupCode.parse('MT:M5L90MP500K64J0000'),
        _fails(MatterSetupCodeProblem.format),
      );
      expect(
        () => MatterSetupCode.parse('MT:M5L90MP500K64J0000!'),
        _fails(MatterSetupCodeProblem.format),
      );
      expect(
        () => MatterSetupCode.parse('MT:'),
        _fails(MatterSetupCodeProblem.format),
      );
    });
  });

  group('typed code', () {
    test('11 digits, however they are spaced', () {
      for (final text in ['34970112332', '3497-011-2332', ' 3497 011 2332 ']) {
        final code = MatterSetupCode.parse(text);
        expect(code.passcode, 20202021);
        expect(code.discriminator, 15);
        expect(code.shortDiscriminator, isTrue);
        expect(code.vendorId, isNull);
        expect(code.fromQr, isFalse);
      }
    });

    test('21 digits carry the maker and the product', () {
      // connectedhomeip TestManualCode: discriminator 2560, passcode
      // 12345679, vendor 1, product 1, before its check digit.
      const body = '64129507530000100001';
      final valid = [
        for (var d = 0; d < 10; d++)
          if (matterVerhoeffValid('$body$d')) '$body$d',
      ];
      expect(valid, hasLength(1));
      final code = MatterSetupCode.parse(valid.single);
      expect(code.discriminator, 2560 >> 8);
      expect(code.passcode, 12345679);
      expect(code.vendorId, 1);
      expect(code.productId, 1);
      // The short form of the same device.
      final short = MatterSetupCode.parse(
        [
          for (var d = 0; d < 10; d++)
            if (matterVerhoeffValid('2412950753$d')) '2412950753$d',
        ].single,
      );
      expect(short.discriminator, 10);
      expect(short.passcode, 12345679);
      expect(short.vendorId, isNull);
    });

    test('codes no device may use are refused', () {
      // Passcode 11111111 with discriminator 0.
      const body = '0027590678';
      final text = [
        for (var d = 0; d < 10; d++)
          if (matterVerhoeffValid('$body$d')) '$body$d',
      ].single;
      expect(
        () => MatterSetupCode.parse(text),
        _fails(MatterSetupCodeProblem.passcode),
      );
    });

    test('one wrong digit is caught', () {
      expect(
        () => MatterSetupCode.parse('34970112342'),
        _fails(MatterSetupCodeProblem.checksum),
      );
      // Two neighbours swapped.
      expect(
        () => MatterSetupCode.parse('34970112323'),
        _fails(MatterSetupCodeProblem.checksum),
      );
    });

    test('anything else is not a code', () {
      for (final text in ['', '1234', '3497011233a', '349701123321']) {
        expect(
          () => MatterSetupCode.parse(text),
          _fails(MatterSetupCodeProblem.format),
          reason: text,
        );
      }
    });
  });
}
