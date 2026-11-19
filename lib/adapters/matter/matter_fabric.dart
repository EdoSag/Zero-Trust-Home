import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

import 'der.dart';

/// A home's own Matter network ("fabric"). Devices added to the home trust
/// its root certificate, and every phone of the home proves itself with a
/// certificate signed by the root key. Because the key lives in the vault,
/// a new phone signs in and controls the devices without pairing them
/// again, and no company holds a key to the home.
@immutable
class MatterFabric {
  const MatterFabric({
    required this.homeId,
    required this.fabricId,
    required this.caKey,
    required this.rootCert,
    required this.ipk,
    required this.adminCat,
  });

  /// One fabric per home.
  final String homeId;

  /// 64 bits, 16 hex digits (ids stay text: they don't fit every number
  /// type the app runs on).
  final String fabricId;

  /// The root key: 32 bytes, hex. Whoever has it can add controllers.
  final String caKey;

  /// The root certificate, X.509 DER.
  final Uint8List rootCert;

  /// The fabric's shared group key ("identity protection key"), 16 bytes.
  final Uint8List ipk;

  /// The tag every phone's certificate carries, 8 hex digits. Devices give
  /// administrator rights to the tag, not to one phone, so any phone of
  /// the home can control them.
  final String adminCat;

  /// The vault item's id: made from the home's id, so two phones that both
  /// make the home's fabric write the same item instead of two fabrics.
  String get id => itemId(homeId);

  static String itemId(String homeId) =>
      const Uuid().v5(Namespace.url.value, 'zerotrust-home:fabric:$homeId');

  /// False for an item this version can't use (damaged, or written
  /// differently by a newer app). It must be kept, never replaced: the
  /// home's devices only trust the key inside it.
  bool get isUsable =>
      homeId.isNotEmpty &&
      fabricId.length == 16 &&
      caKey.length == 64 &&
      ipk.length == 16 &&
      adminCat.length == 8 &&
      rootCert.isNotEmpty;

  /// What devices are told to trust as administrator.
  String get adminSubject => 'FFFFFFFD$adminCat';

  /// A new fabric with fresh keys.
  factory MatterFabric.create(String homeId, {Random? random, DateTime? now}) {
    final rng = random ?? Random.secure();
    final key = matterNewKey(rng);
    return MatterFabric(
      homeId: homeId,
      fabricId: _randomId(rng),
      caKey: bytesHex(key.privateKey),
      rootCert: matterBuildCert(
        signerKey: key.privateKey,
        serial: _randomSerial(rng),
        issuer: [(_oidRcacId, _randomId(rng))],
        notBefore: _backdated(now),
        publicKey: key.publicKey,
        isCa: true,
      ),
      ipk: _randomBytes(rng, 16),
      // Identifier in the top 16 bits, version 1 below; neither may be 0.
      adminCat:
          '${(1 + rng.nextInt(0xFFFE)).toRadixString(16).padLeft(4, '0')}0001'
              .toUpperCase(),
    );
  }

  /// A certificate for one phone, for the public key it made (65 bytes,
  /// uncompressed). [nodeId] keeps a phone the node it already was;
  /// without it the phone becomes a new node.
  MatterNode issueController(
    Uint8List publicKey, {
    String? nodeId,
    Random? random,
    DateTime? now,
  }) => _issue(publicKey, nodeId, random, now, admin: true);

  /// A certificate for a device being added, from the signing request it
  /// sent (PKCS#10 DER). [nodeId] is the id the device is being added
  /// under (see [matterNewNodeId]). Throws [MatterCertException] when the
  /// request is not properly signed.
  MatterNode issueDevice(
    Uint8List csr, {
    String? nodeId,
    Random? random,
    DateTime? now,
  }) => _issue(matterCsrPublicKey(csr), nodeId, random, now, admin: false);

  MatterNode _issue(
    Uint8List publicKey,
    String? id,
    Random? random,
    DateTime? now, {
    required bool admin,
  }) {
    final rng = random ?? Random.secure();
    final nodeId = id ?? _randomId(rng);
    if (!RegExp(r'^[0-9A-F]{16}$').hasMatch(nodeId)) {
      throw const MatterCertException('Not a node id');
    }
    final root = _CertInfo.read(rootCert);
    return MatterNode(
      nodeId: nodeId,
      cert: matterBuildCert(
        signerKey: hexBytes(caKey),
        serial: _randomSerial(rng),
        issuerDer: root.subject,
        authorityKeyId: root.subjectKeyId,
        notBefore: _backdated(now),
        subject: [
          (_oidNodeId, nodeId),
          (_oidFabricId, fabricId),
          if (admin) (_oidNocCat, adminCat),
        ],
        publicKey: publicKey,
        isCa: false,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'homeId': homeId,
    'fabricId': fabricId,
    'caKey': caKey,
    'rootCert': base64Encode(rootCert),
    'ipk': bytesHex(ipk),
    'adminCat': adminCat,
  };

  /// Never throws: an item that can't be read comes back not [isUsable].
  static MatterFabric fromJson(Map<String, dynamic> json) {
    String text(String key) => json[key] is String ? json[key] as String : '';
    Uint8List bytes(Uint8List Function() read) {
      try {
        return read();
      } on Object {
        return Uint8List(0);
      }
    }

    return MatterFabric(
      homeId: text('homeId'),
      fabricId: text('fabricId'),
      caKey: text('caKey'),
      rootCert: bytes(() => base64Decode(text('rootCert'))),
      ipk: bytes(() => hexBytes(text('ipk'))),
      adminCat: text('adminCat'),
    );
  }
}

/// A node of the fabric: a phone or a device, with its certificate.
@immutable
class MatterNode {
  const MatterNode({required this.nodeId, required this.cert});

  /// 16 hex digits.
  final String nodeId;

  /// X.509 DER, signed by the fabric's root.
  final Uint8List cert;
}

class MatterCertException implements Exception {
  const MatterCertException(this.message);
  final String message;
  @override
  String toString() => 'MatterCertException: $message';
}

// Matter's own name attributes: who a certificate is for.
const _oidNodeId = '1.3.6.1.4.1.37244.1.1';
const _oidRcacId = '1.3.6.1.4.1.37244.1.4';
const _oidFabricId = '1.3.6.1.4.1.37244.1.5';
const _oidNocCat = '1.3.6.1.4.1.37244.1.6';

const _oidEcPublicKey = '1.2.840.10045.2.1';
const _oidP256 = '1.2.840.10045.3.1.7';
const _oidEcdsaSha256 = '1.2.840.10045.4.3.2';

final _p256 = ECCurve_secp256r1();

/// A new P-256 key pair: 32 private bytes, 65 public (uncompressed).
({Uint8List privateKey, Uint8List publicKey}) matterNewKey([Random? random]) {
  final rng = random ?? Random.secure();
  while (true) {
    final d = bytesBigInt(_randomBytes(rng, 32));
    if (d == BigInt.zero || d >= _p256.n) continue;
    return (
      privateKey: bigIntBytes(d, length: 32),
      publicKey: (_p256.G * d)!.getEncoded(false),
    );
  }
}

/// Signs with ECDSA and SHA-256; the result is the DER pair certificates
/// and Matter's Java API use.
Uint8List matterSign(List<int> privateKey, List<int> message) {
  final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
    ..init(
      true,
      PrivateKeyParameter<ECPrivateKey>(
        ECPrivateKey(bytesBigInt(privateKey), _p256),
      ),
    );
  final signature =
      signer.generateSignature(Uint8List.fromList(message)) as ECSignature;
  return derSequence([derBigInt(signature.r), derBigInt(signature.s)]);
}

bool matterVerify(List<int> publicKey, List<int> message, List<int> signature) {
  try {
    final parts = derRead(Uint8List.fromList(signature)).children;
    if (parts.length != 2) return false;
    final verifier = ECDSASigner(SHA256Digest())
      ..init(
        false,
        PublicKeyParameter<ECPublicKey>(
          ECPublicKey(_p256.curve.decodePoint(publicKey), _p256),
        ),
      );
    return verifier.verifySignature(
      Uint8List.fromList(message),
      ECSignature(bytesBigInt(parts[0].content), bytesBigInt(parts[1].content)),
    );
  } on Object {
    return false;
  }
}

Uint8List _name(List<(String, String)> attributes) => derSequence([
  for (final (oid, value) in attributes)
    derSet([
      derSequence([derOid(oid), derUtf8(value)]),
    ]),
]);

Uint8List _keyId(List<int> publicKey) =>
    SHA1Digest().process(Uint8List.fromList(publicKey));

Uint8List _extension(String oid, List<int> value, {bool critical = false}) =>
    derSequence([derOid(oid), if (critical) derBool(true), derOctets(value)]);

/// Builds and signs a Matter certificate in the exact shape the standard's
/// own tool gives: a root when [isCa] (it names and signs itself, so pass
/// [issuer]), else a node certificate under [issuerDer].
Uint8List matterBuildCert({
  required List<int> signerKey,
  required List<int> serial,
  List<(String, String)>? issuer,
  Uint8List? issuerDer,
  List<int>? authorityKeyId,
  required DateTime notBefore,
  DateTime? notAfter,
  List<(String, String)>? subject,
  required List<int> publicKey,
  required bool isCa,
}) {
  final issuerName = issuerDer ?? _name(issuer!);
  final subjectName = subject == null ? issuerName : _name(subject);
  final keyId = _keyId(publicKey);
  final tbs = derSequence([
    derExplicit(0, derInt([2])), // X.509 version 3.
    derInt(serial),
    derSequence([derOid(_oidEcdsaSha256)]),
    issuerName,
    derSequence([
      derTime(notBefore),
      // Year 9999 means "no end date"; Matter reads it that way too.
      derTime(notAfter ?? DateTime.utc(9999, 12, 31, 23, 59, 59)),
    ]),
    subjectName,
    derSequence([
      derSequence([derOid(_oidEcPublicKey), derOid(_oidP256)]),
      derBits(publicKey),
    ]),
    derExplicit(
      3,
      derSequence([
        // Basic constraints: a certificate authority, or not.
        _extension(
          '2.5.29.19',
          derSequence([if (isCa) derBool(true)]),
          critical: true,
        ),
        // Key usage: sign certificates and revocation lists, or sign data.
        _extension(
          '2.5.29.15',
          isCa ? derBits([0x06], unused: 1) : derBits([0x80], unused: 7),
          critical: true,
        ),
        // Extended key usage: client and server authentication.
        if (!isCa)
          _extension(
            '2.5.29.37',
            derSequence([
              derOid('1.3.6.1.5.5.7.3.2'),
              derOid('1.3.6.1.5.5.7.3.1'),
            ]),
            critical: true,
          ),
        _extension('2.5.29.14', derOctets(keyId)),
        _extension(
          '2.5.29.35',
          derSequence([derImplicit(0, authorityKeyId ?? keyId)]),
        ),
      ]),
    ),
  ]);
  return derSequence([
    tbs,
    derSequence([derOid(_oidEcdsaSha256)]),
    derBits(matterSign(signerKey, tbs)),
  ]);
}

/// The public key (65 bytes) of a PKCS#10 signing request, once its own
/// signature is checked: the sender really holds the private key.
Uint8List matterCsrPublicKey(Uint8List csr) {
  try {
    final parts = derRead(csr).children;
    final info = parts[0];
    final spki = info.children[2].children;
    final algorithm = spki[0].children;
    final ec = derOid(_oidEcPublicKey);
    final p256 = derOid(_oidP256);
    if (!listEquals(algorithm[0].whole, ec) ||
        !listEquals(algorithm[1].whole, p256)) {
      throw const MatterCertException('The request is not for a P-256 key');
    }
    // Bit strings start with their count of unused bits: none here.
    final publicKey = spki[1].content.sublist(1);
    final signature = parts[2].content.sublist(1);
    if (publicKey.length != 65 || publicKey[0] != 0x04) {
      throw const MatterCertException('The request has no P-256 key');
    }
    if (!matterVerify(publicKey, info.whole, signature)) {
      throw const MatterCertException('The request is not signed by its key');
    }
    return publicKey;
  } on MatterCertException {
    rethrow;
  } on Object {
    throw const MatterCertException('Not a signing request');
  }
}

/// A PKCS#10 signing request for a key, as a device or a phone sends one.
Uint8List matterBuildCsr(List<int> privateKey, List<int> publicKey) {
  final info = derSequence([
    derInt([0]),
    derSequence([
      derSet([
        derSequence([derOid('2.5.4.10'), derUtf8('CSR')]),
      ]),
    ]),
    derSequence([
      derSequence([derOid(_oidEcPublicKey), derOid(_oidP256)]),
      derBits(publicKey),
    ]),
    derExplicit(0, const []),
  ]);
  return derSequence([
    info,
    derSequence([derOid(_oidEcdsaSha256)]),
    derBits(matterSign(privateKey, info)),
  ]);
}

/// What issuing under a certificate needs from it.
class _CertInfo {
  _CertInfo(this.subject, this.subjectKeyId);
  final Uint8List subject;
  final Uint8List subjectKeyId;

  static _CertInfo read(Uint8List cert) {
    // version, serial, algorithm, issuer, validity, subject, key, extensions
    final tbs = derRead(cert).children[0].children;
    final key = tbs[6].children[1].content.sublist(1);
    return _CertInfo(tbs[5].whole, _keyId(key));
  }
}

Uint8List _randomBytes(Random rng, int count) =>
    Uint8List.fromList([for (var i = 0; i < count; i++) rng.nextInt(256)]);

/// A fresh node id for a device about to be added: 16 hex digits.
String matterNewNodeId([Random? random]) =>
    _randomId(random ?? Random.secure());

/// A 64-bit id that is never 0 and stays below Matter's reserved ranges
/// (and positive in Java).
String _randomId(Random rng) {
  final bytes = _randomBytes(rng, 8);
  bytes[0] &= 0x7F;
  bytes[7] |= 0x01;
  return bytesHex(bytes).toUpperCase();
}

Uint8List _randomSerial(Random rng) {
  final bytes = _randomBytes(rng, 8);
  bytes[0] = (bytes[0] & 0x7F) | 0x01;
  return bytes;
}

/// A day back: devices and phones with a slow clock still accept it.
DateTime _backdated(DateTime? now) =>
    (now ?? DateTime.now()).toUtc().subtract(const Duration(days: 1));
