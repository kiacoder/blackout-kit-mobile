import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/vault_record_experiment.dart';

void main() {
  final codec = VaultRecordExperiment();
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  final data = Uint8List.fromList(utf8.encode('fixture payload'));

  Future<Uint8List> seal([Uint8List? value]) => codec.seal(
        key: key,
        box: 'configs',
        recordKey: 'config_fixture',
        plaintext: value ?? data,
      );

  Future<Uint8List> open(
    Uint8List envelope, {
    List<int>? withKey,
    String box = 'configs',
    String recordKey = 'config_fixture',
  }) =>
      codec.open(
        key: withKey ?? key,
        box: box,
        recordKey: recordKey,
        envelope: envelope,
      );

  test('authenticated envelope round trips binary and empty records', () async {
    for (final value in [
      data,
      Uint8List(0),
      Uint8List.fromList([0, 255, 10])
    ]) {
      expect(await open(await seal(value)), value);
    }
  });

  test('independent AES-GCM interoperability fixture', () async {
    // Python cryptography AESGCM, key 00..1f, nonce 00..0b, same JSON AAD.
    const hex = '424b5633000102030405060708090a0b'
        '216bae6fb097a73bfd20eee7de881c9c6b60dd54b02b039d22be5af43fa752';
    final envelope = Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
    expect(await open(envelope), data);
  });

  test('repeated encryption uses different nonce bytes', () async {
    final first = await seal();
    final second = await seal();
    expect(first.sublist(4, 16), isNot(second.sublist(4, 16)));
    expect(await open(first), await open(second));
    expect(key, List.generate(32, (i) => i));
  });

  test('nonce, ciphertext and tag modifications fail authentication', () async {
    final original = await seal();
    for (final index in [4, 16, original.length - 1]) {
      final modified = Uint8List.fromList(original);
      modified[index] ^= 1;
      await expectLater(
          open(modified), throwsA(isA<SecretBoxAuthenticationError>()));
    }
  });

  test('wrong key or record context rejects a valid envelope', () async {
    final envelope = await seal();
    await expectLater(open(envelope, withKey: Uint8List(32)),
        throwsA(isA<SecretBoxAuthenticationError>()));
    await expectLater(open(envelope, box: 'sources'),
        throwsA(isA<SecretBoxAuthenticationError>()));
    await expectLater(open(envelope, recordKey: 'other'),
        throwsA(isA<SecretBoxAuthenticationError>()));
  });

  test('unknown version, truncated and oversize inputs fail closed', () async {
    final envelope = await seal();
    final modified = Uint8List.fromList(envelope)..[3] = 0;
    await expectLater(open(modified), throwsFormatException);
    await expectLater(open(Uint8List(31)), throwsFormatException);
    await expectLater(open(envelope.sublist(0, envelope.length - 1)),
        throwsA(isA<SecretBoxAuthenticationError>()));
    await expectLater(seal(Uint8List(VaultRecordExperiment.maxRecordBytes + 1)),
        throwsArgumentError);
    await expectLater(
        open(Uint8List(VaultRecordExperiment.maxRecordBytes + 33)),
        throwsFormatException);
  });

  test('invalid key and context are rejected', () async {
    final envelope = await seal();
    await expectLater(
        open(envelope, withKey: Uint8List(31)), throwsArgumentError);
    await expectLater(open(envelope, box: 'unknown'), throwsArgumentError);
    await expectLater(open(envelope, recordKey: ''), throwsArgumentError);
    await expectLater(
        open(envelope, recordKey: 'x' * 1025), throwsArgumentError);
  });
}
