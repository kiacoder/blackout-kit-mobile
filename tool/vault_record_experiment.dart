// Development-only format experiment. Not used by the shipping Hive vault.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Versioned AES-256-GCM envelope for one record. The caller must supply a
/// dedicated v3 key, not reuse the existing Hive key.
class VaultRecordExperiment {
  static const _magic = [0x42, 0x4b, 0x56, 0x33]; // BKV3
  static const _nonceLength = 12;
  static const _tagLength = 16;
  static const _overhead = 4 + _nonceLength + _tagLength;
  static const maxRecordBytes = 8 * 1024 * 1024;
  static const _boxes = {'configs', 'sources', 'test_results'};
  static const _metadataBoxes = {'manifest', 'commit'};
  final _cipher = AesGcm.with256bits();

  List<int> _context(String box, String recordKey) {
    if ((!_boxes.contains(box) && !_metadataBoxes.contains(box)) ||
        (_metadataBoxes.contains(box) &&
            !RegExp(r'^[0-9a-f]{32}$').hasMatch(recordKey)) ||
        recordKey.isEmpty ||
        utf8.encode(recordKey).length > 1024) {
      throw ArgumentError('Invalid vault record context');
    }
    return utf8.encode(jsonEncode(['BlackoutKit/vault/v3', box, recordKey]));
  }

  SecretKeyData _key(List<int> key) {
    if (key.length != 32 || key.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Expected 32-byte vault key');
    }
    return SecretKeyData(
      Uint8List.fromList(key),
      overwriteWhenDestroyed: true,
    );
  }

  Future<Uint8List> seal({
    required List<int> key,
    required String box,
    required String recordKey,
    required Uint8List plaintext,
  }) async {
    if (plaintext.length > maxRecordBytes) {
      throw ArgumentError('Vault record too large');
    }
    final aad = _context(box, recordKey);
    final secret = _key(key);
    try {
      // The library generates a fresh secure random nonce per encryption.
      final encrypted = await _cipher.encrypt(
        plaintext,
        secretKey: secret,
        aad: aad,
      );
      return Uint8List.fromList([
        ..._magic,
        ...encrypted.nonce,
        ...encrypted.cipherText,
        ...encrypted.mac.bytes,
      ]);
    } finally {
      secret.destroy();
    }
  }

  Future<Uint8List> open({
    required List<int> key,
    required String box,
    required String recordKey,
    required Uint8List envelope,
  }) async {
    if (envelope.length < _overhead ||
        envelope.length > maxRecordBytes + _overhead ||
        !_magic.asMap().entries.every((e) => envelope[e.key] == e.value)) {
      throw const FormatException('Invalid vault record envelope');
    }
    final aad = _context(box, recordKey);
    final secret = _key(key);
    try {
      final payload = SecretBox(
        envelope.sublist(4 + _nonceLength, envelope.length - _tagLength),
        nonce: envelope.sublist(4, 4 + _nonceLength),
        mac: Mac(envelope.sublist(envelope.length - _tagLength)),
      );
      return Uint8List.fromList(await _cipher.decrypt(
        payload,
        secretKey: secret,
        aad: aad,
      ));
    } finally {
      secret.destroy();
    }
  }
}
