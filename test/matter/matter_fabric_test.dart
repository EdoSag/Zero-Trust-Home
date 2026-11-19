import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zerotrust_home/adapters/matter/der.dart';
import 'package:zerotrust_home/adapters/matter/matter_fabric.dart';

// Test certificates of the Matter SDK (connectedhomeip v1.6.1.0,
// src/credentials/tests/CHIPCert_test_vectors.cpp), made by its chip-cert
// tool. A certificate built here from the same inputs must be the same,
// byte for byte, up to the signature (ECDSA signatures differ each time).
const _root01 =
    '3082019e30820143a0030201020208534c458273623514300a06082a8648ce3d0403023022'
    '3120301e060a2b0601040182a27c01040c1043414341434143413030303030303031301e17'
    '0d3230313031353134323334335a170d3430313031353134323334325a30223120301e060a'
    '2b0601040182a27c01040c1043414341434143413030303030303031305930130607'
    '2a8648ce3d020106082a8648ce3d030107034200043b88460ec9687a5d0f3b4b3b13fcd299'
    'c2f6d5051d003ee49c9924cf98f4f780eb20fd37c8d358347f5f87d08c3213e540af11bab9'
    '137e49354f0c5b6343de63a3633061300f0603551d130101ff040530030101ff300e060355'
    '1d0f0101ff040403020106301d0603551d0e04160414cc1308af82cfee505eb23b57bfe86a'
    '311665535f301f0603551d23041830168014cc1308af82cfee505eb23b57bfe86a31166553'
    '5f300a06082a8648ce3d0403020349003046022100f7f0092690494e46c8b1c5cbd1a5085e'
    '1e65d4360f98e96c4e8e495dc5e216d0022100bfa23d8f57470d89fddaf03f0464b0ae8e1f'
    '956d6f67a31124385824689780a9';
const _root01Key =
    'fcddfd9112b30d240f6ae6de27a2029e7bb6e74377e3b7975d76d23de3c36814';
const _root01Public =
    '043b88460ec9687a5d0f3b4b3b13fcd299c2f6d5051d003ee49c9924cf98f4f780eb20fd37'
    'c8d358347f5f87d08c3213e540af11bab9137e49354f0c5b6343de63';
const _node0102 =
    '308201df30820186a00302010202080d90935346b05cbc300a06082a8648ce3d0403023022'
    '3120301e060a2b0601040182a27c01040c1043414341434143413030303030303031301e17'
    '0d3230313031353134323334335a170d3430313031353134323334325a30443120301e060a'
    '2b0601040182a27c01010c10444544454445444530303031303030323120301e060a2b0601'
    '040182a27c01050c10464142303030303030303030303031443059301306072a8648ce3d02'
    '0106082a8648ce3d03010703420004965f78c537ece1b8c34a7b98b9aa45f13563a502b197'
    '9a607bd0c41988bdd0f0bbb89816c207e3b515d9264159f78bd0978e32d74c6d055a149e8e'
    '9dba4019bfa38183308180300c0603551d130101ff04023000300e0603551d0f0101ff0404'
    '0302078030200603551d250101ff0416301406082b0601050507030206082b060105050703'
    '01301d0603551d0e04160414567b4f20e4b9c7bd27b29b3dce6a76f7cd8eccb6301f060355'
    '1d23041830168014cc1308af82cfee505eb23b57bfe86a311665535f300a06082a8648ce3d'
    '040302034700304402206058114ba72182fcf6301f7a081bca5a848202431a52fdbff497d8'
    'dd6f9a595902207badccd6a56d70efd8c97c496eba7e2801d7337dcff74d78e46ecd3a08cc'
    'bae3';
const _node0102Public =
    '04965f78c537ece1b8c34a7b98b9aa45f13563a502b1979a607bd0c41988bdd0f0bbb89816'
    'c207e3b515d9264159f78bd0978e32d74c6d055a149e8e9dba4019bf';

final _from = DateTime.utc(2020, 10, 15, 14, 23, 43);
final _to = DateTime.utc(2040, 10, 15, 14, 23, 42);

/// The signed part of a certificate, and its signature.
({Uint8List tbs, Uint8List signature}) _parts(Uint8List cert) {
  final parts = derRead(cert).children;
  return (tbs: parts[0].whole, signature: parts[2].content.sublist(1));
}

/// The name attributes of a certificate's subject, in order.
List<String> _subject(Uint8List cert) => [
  for (final set in derRead(cert).children[0].children[5].children)
    String.fromCharCodes(set.children[0].children[1].content),
];

void main() {
  test('a root certificate is what the Matter SDK\'s tool makes', () {
    final cert = matterBuildCert(
      signerKey: hexBytes(_root01Key),
      serial: hexBytes('534c458273623514'),
      issuer: [('1.3.6.1.4.1.37244.1.4', 'CACACACA00000001')],
      notBefore: _from,
      notAfter: _to,
      publicKey: hexBytes(_root01Public),
      isCa: true,
    );
    final ours = _parts(cert);
    final theirs = _parts(hexBytes(_root01));
    expect(bytesHex(ours.tbs), bytesHex(theirs.tbs));
    expect(
      matterVerify(hexBytes(_root01Public), ours.tbs, ours.signature),
      isTrue,
    );
    // The same check accepts the SDK's own signature.
    expect(
      matterVerify(hexBytes(_root01Public), theirs.tbs, theirs.signature),
      isTrue,
    );
  });

  test('a node certificate is what the Matter SDK\'s tool makes', () {
    final root = derRead(hexBytes(_root01)).children[0].children;
    final cert = matterBuildCert(
      signerKey: hexBytes(_root01Key),
      serial: hexBytes('0d90935346b05cbc'),
      issuerDer: root[5].whole,
      authorityKeyId: hexBytes('cc1308af82cfee505eb23b57bfe86a311665535f'),
      notBefore: _from,
      notAfter: _to,
      subject: [
        ('1.3.6.1.4.1.37244.1.1', 'DEDEDEDE00010002'),
        ('1.3.6.1.4.1.37244.1.5', 'FAB000000000001D'),
      ],
      publicKey: hexBytes(_node0102Public),
      isCa: false,
    );
    final ours = _parts(cert);
    expect(bytesHex(ours.tbs), bytesHex(_parts(hexBytes(_node0102)).tbs));
    expect(
      matterVerify(hexBytes(_root01Public), ours.tbs, ours.signature),
      isTrue,
    );
  });

  group('a home\'s fabric', () {
    final fabric = MatterFabric.create(
      'home-1',
      random: Random(7),
      now: DateTime.utc(2026, 11, 19, 12),
    );
    final rootKey = matterNewKey(Random(7)).publicKey;

    test('has its own ids and a root that signs itself', () {
      expect(fabric.homeId, 'home-1');
      expect(fabric.id, MatterFabric.itemId('home-1'));
      expect(fabric.id, isNot(MatterFabric.itemId('home-2')));
      expect(fabric.isUsable, isTrue);
      expect(fabric.fabricId, matches(RegExp(r'^[0-7][0-9A-F]{15}$')));
      expect(fabric.adminCat, matches(RegExp(r'^[0-9A-F]{4}0001$')));
      expect(fabric.adminCat.substring(0, 4), isNot('0000'));
      expect(fabric.adminSubject, 'FFFFFFFD${fabric.adminCat}');
      expect(fabric.ipk, hasLength(16));
      final root = _parts(fabric.rootCert);
      expect(matterVerify(rootKey, root.tbs, root.signature), isTrue);
      // Valid from the day before, with no end date.
      final validity = derRead(fabric.rootCert).children[0].children[4];
      expect(
        String.fromCharCodes(validity.children[0].content),
        '261118120000Z',
      );
      expect(validity.children[1].tag, 0x18);
      expect(
        String.fromCharCodes(validity.children[1].content),
        '99991231235959Z',
      );
    });

    test('two homes never share keys', () {
      final other = MatterFabric.create('home-2');
      final again = MatterFabric.create('home-2');
      expect(other.caKey, isNot(again.caKey));
      expect(other.fabricId, isNot(again.fabricId));
      expect(bytesHex(other.ipk), isNot(bytesHex(again.ipk)));
    });

    test('a phone gets a certificate with the administrator tag', () {
      final phone = matterNewKey(Random(1));
      final node = fabric.issueController(phone.publicKey, random: Random(2));
      expect(_subject(node.cert), [
        node.nodeId,
        fabric.fabricId,
        fabric.adminCat,
      ]);
      final cert = _parts(node.cert);
      expect(matterVerify(rootKey, cert.tbs, cert.signature), isTrue);
      // Under the root: its name as issuer, its key id as authority.
      final tbs = derRead(node.cert).children[0].children;
      final rootTbs = derRead(fabric.rootCert).children[0].children;
      expect(tbs[3].whole, rootTbs[5].whole);
      expect(
        bytesHex(tbs[6].children[1].content.sublist(1)),
        bytesHex(phone.publicKey),
      );
      // Another phone is another node.
      final second = fabric.issueController(phone.publicKey, random: Random(3));
      expect(second.nodeId, isNot(node.nodeId));
    });

    test('a device gets one from its signing request, without the tag', () {
      final device = matterNewKey(Random(4));
      final csr = matterBuildCsr(device.privateKey, device.publicKey);
      final node = fabric.issueDevice(csr, random: Random(5));
      expect(_subject(node.cert), [node.nodeId, fabric.fabricId]);
      final cert = _parts(node.cert);
      expect(matterVerify(rootKey, cert.tbs, cert.signature), isTrue);
    });

    test('a signing request signed by another key is refused', () {
      final device = matterNewKey(Random(4));
      final other = matterNewKey(Random(6));
      expect(
        () => fabric.issueDevice(
          matterBuildCsr(other.privateKey, device.publicKey),
        ),
        throwsA(isA<MatterCertException>()),
      );
      expect(
        () => fabric.issueDevice(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<MatterCertException>()),
      );
    });

    test('survives being saved and read back', () {
      final back = MatterFabric.fromJson(fabric.toJson());
      expect(back.isUsable, isTrue);
      expect(back.id, fabric.id);
      expect(back.fabricId, fabric.fabricId);
      expect(back.caKey, fabric.caKey);
      expect(back.rootCert, fabric.rootCert);
      expect(back.ipk, fabric.ipk);
      expect(back.adminCat, fabric.adminCat);
      // Anything else is read without throwing, and marked unusable.
      expect(MatterFabric.fromJson(const {}).isUsable, isFalse);
      for (final bad in [
        {'caKey': 'ab'},
        {'rootCert': '***'},
        {'ipk': 'xyz'},
        {'fabricId': 7},
      ]) {
        expect(
          MatterFabric.fromJson({...fabric.toJson(), ...bad}).isUsable,
          isFalse,
          reason: '$bad',
        );
      }
    });
  });
}
