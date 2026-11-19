import 'dart:typed_data';

/// What a Matter device's sticker says: the QR code (`MT:...`) or the 11 or
/// 21 digit code under it. Both carry the passcode that proves the person
/// holding the phone also holds the device.
class MatterSetupCode {
  const MatterSetupCode({
    required this.passcode,
    required this.discriminator,
    required this.shortDiscriminator,
    this.vendorId,
    this.productId,
    this.onNetwork = false,
    this.bluetooth = false,
    this.fromQr = false,
  });

  /// 1 to 99999998.
  final int passcode;

  /// Tells this device from others in pairing mode. 12 bits from a QR code;
  /// a typed code carries only the top 4 ([shortDiscriminator] is true).
  final int discriminator;
  final bool shortDiscriminator;

  /// Who made it, when the code says so.
  final int? vendorId;
  final int? productId;

  /// How the QR code says the device can be found. A typed code says
  /// nothing: both are false.
  final bool onNetwork;
  final bool bluetooth;
  final bool fromQr;

  /// Reads either kind of code. Spaces and dashes in a typed code are
  /// fine. Throws [MatterSetupCodeException] with what is wrong.
  static MatterSetupCode parse(String input) {
    final text = input.trim();
    if (text.toUpperCase().startsWith('MT:')) return _parseQr(text);
    return _parseManual(text.replaceAll(RegExp(r'[\s-]'), ''));
  }

  /// Whether [input] looks like a Matter QR code at all (a camera sees
  /// other QR codes too).
  static bool isQr(String input) =>
      input.trim().toUpperCase().startsWith('MT:');

  @override
  String toString() =>
      'MatterSetupCode(discriminator $discriminator'
      '${shortDiscriminator ? ' short' : ''}, vendor $vendorId, '
      'product $productId)';
}

enum MatterSetupCodeProblem {
  /// Not a Matter code at all: wrong length, wrong characters.
  format,

  /// A digit is wrong (the last digit checks the others).
  checksum,

  /// A code no device may use (00000000, 12345678 and the like).
  passcode,

  /// A newer kind of code than this app knows.
  version,
}

class MatterSetupCodeException implements Exception {
  const MatterSetupCodeException(this.problem);
  final MatterSetupCodeProblem problem;
  @override
  String toString() => 'MatterSetupCodeException(${problem.name})';
}

const _base38 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-.';

/// Passcodes the standard forbids.
const _forbidden = {
  0,
  11111111,
  22222222,
  33333333,
  44444444,
  55555555,
  66666666,
  77777777,
  88888888,
  99999999,
  12345678,
  87654321,
};

void _checkPasscode(int passcode) {
  if (passcode > 99999998 || _forbidden.contains(passcode)) {
    throw const MatterSetupCodeException(MatterSetupCodeProblem.passcode);
  }
}

/// Base 38: 5 characters hold 3 bytes, 4 hold 2, 2 hold 1, lowest first.
Uint8List matterBase38Decode(String text) {
  const bytesFor = {5: 3, 4: 2, 2: 1};
  final out = BytesBuilder();
  for (var at = 0; at < text.length; at += 5) {
    final chunk = text.substring(
      at,
      at + 5 > text.length ? text.length : at + 5,
    );
    final count = bytesFor[chunk.length];
    if (count == null) {
      throw const MatterSetupCodeException(MatterSetupCodeProblem.format);
    }
    var value = 0;
    for (var i = chunk.length - 1; i >= 0; i--) {
      final digit = _base38.indexOf(chunk[i]);
      if (digit < 0) {
        throw const MatterSetupCodeException(MatterSetupCodeProblem.format);
      }
      value = value * 38 + digit;
    }
    if (value >= 1 << (8 * count)) {
      throw const MatterSetupCodeException(MatterSetupCodeProblem.format);
    }
    for (var i = 0; i < count; i++) {
      out.addByte((value >> (8 * i)) & 0xFF);
    }
  }
  return out.toBytes();
}

MatterSetupCode _parseQr(String text) {
  // "MT:" then one payload; a '*' would start another device's payload.
  final body = text.substring(3).split('*').first.toUpperCase();
  final bytes = matterBase38Decode(body);
  // 88 bits, packed from the lowest bit up; optional extras follow.
  if (bytes.length < 11) {
    throw const MatterSetupCodeException(MatterSetupCodeProblem.format);
  }
  var at = 0;
  int take(int bits) {
    var value = 0;
    for (var i = 0; i < bits; i++, at++) {
      if (bytes[at >> 3] & (1 << (at & 7)) != 0) value |= 1 << i;
    }
    return value;
  }

  final version = take(3);
  final vendorId = take(16);
  final productId = take(16);
  take(2); // Commissioning flow: standard, user action, custom.
  final rendezvous = take(8);
  final discriminator = take(12);
  final passcode = take(27);
  final padding = take(4);
  if (version != 0) {
    throw const MatterSetupCodeException(MatterSetupCodeProblem.version);
  }
  if (padding != 0) {
    throw const MatterSetupCodeException(MatterSetupCodeProblem.format);
  }
  _checkPasscode(passcode);
  return MatterSetupCode(
    passcode: passcode,
    discriminator: discriminator,
    shortDiscriminator: false,
    vendorId: vendorId == 0 ? null : vendorId,
    productId: productId == 0 ? null : productId,
    bluetooth: rendezvous & 0x02 != 0,
    onNetwork: rendezvous & 0x04 != 0,
    fromQr: true,
  );
}

MatterSetupCode _parseManual(String digits) {
  if (!RegExp(r'^\d+$').hasMatch(digits) ||
      (digits.length != 11 && digits.length != 21)) {
    throw const MatterSetupCodeException(MatterSetupCodeProblem.format);
  }
  if (!matterVerhoeffValid(digits)) {
    throw const MatterSetupCodeException(MatterSetupCodeProblem.checksum);
  }
  final first = int.parse(digits[0]);
  // 8 and 9 are kept for later versions.
  if (first > 7) {
    throw const MatterSetupCodeException(MatterSetupCodeProblem.version);
  }
  final long = first & 0x4 != 0;
  if (long != (digits.length == 21)) {
    throw const MatterSetupCodeException(MatterSetupCodeProblem.format);
  }
  final second = int.parse(digits.substring(1, 6));
  final third = int.parse(digits.substring(6, 10));
  if (second > 0xFFFF || third > 0x1FFF) {
    throw const MatterSetupCodeException(MatterSetupCodeProblem.format);
  }
  final passcode = (second & 0x3FFF) | (third << 14);
  _checkPasscode(passcode);
  int? vendorId;
  int? productId;
  if (long) {
    vendorId = int.parse(digits.substring(10, 15));
    productId = int.parse(digits.substring(15, 20));
    if (vendorId > 0xFFFF || productId > 0xFFFF) {
      throw const MatterSetupCodeException(MatterSetupCodeProblem.format);
    }
  }
  return MatterSetupCode(
    passcode: passcode,
    discriminator: ((first & 0x3) << 2) | (second >> 14),
    shortDiscriminator: true,
    vendorId: vendorId,
    productId: productId,
  );
}

const _verhoeffD = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  [1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
  [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
  [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
  [4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
  [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
  [6, 5, 9, 8, 7, 1, 0, 4, 3, 2],
  [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
  [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
  [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
];
const _verhoeffP = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  [1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
  [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
  [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
  [9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
  [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
  [2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
  [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
];

/// Whether the last digit of [digits] is the Verhoeff check digit of the
/// others (it catches one wrong digit and two swapped ones).
bool matterVerhoeffValid(String digits) {
  var c = 0;
  for (var i = 0; i < digits.length; i++) {
    final digit = digits.codeUnitAt(digits.length - 1 - i) - 0x30;
    c = _verhoeffD[c][_verhoeffP[i % 8][digit]];
  }
  return c == 0;
}
