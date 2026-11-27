// Development-only generation verification. No access to the shipping vault.
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'vault_record_experiment.dart';

class VaultCipherRecord {
  final String box;
  final String recordKey;
  final Uint8List envelope;

  VaultCipherRecord(this.box, this.recordKey, Uint8List envelope)
      : envelope = Uint8List.fromList(envelope);
}

enum VaultGenerationState { absent, staged, committed, locked }

/// Authenticates an entire immutable generation, not just individual records.
/// The caller must supply an independently selected expected generation ID.
/// This does not provide durable filesystem transactions or rollback protection.
class VaultGenerationExperiment {
  static const maxRecords = 10000;
  static const maxGenerationBytes = 64 * 1024 * 1024;
  static const _boxes = {'configs', 'sources', 'test_results'};
  final _codec = VaultRecordExperiment();

  void _validateGeneration(String generation) {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(generation)) {
      throw ArgumentError('Invalid generation identifier');
    }
  }

  Uint8List _copyKey(List<int> key) {
    if (key.length != 32 || key.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError('Expected 32-byte vault key');
    }
    return Uint8List.fromList(key);
  }

  Uint8List _copyMetadata(Uint8List envelope) {
    if (envelope.length > VaultRecordExperiment.maxRecordBytes + 32) {
      throw const FormatException('Oversize vault metadata');
    }
    return Uint8List.fromList(envelope);
  }

  List<VaultCipherRecord> _snapshot(List<VaultCipherRecord> records) {
    if (records.length > maxRecords) {
      throw const FormatException('Too many vault records');
    }
    var bytes = 0;
    final seen = <String>{};
    final copies = <VaultCipherRecord>[];
    for (final record in records) {
      bytes += record.envelope.length;
      if (!_boxes.contains(record.box) ||
          record.recordKey.isEmpty ||
          utf8.encode(record.recordKey).length > 1024 ||
          record.envelope.length > VaultRecordExperiment.maxRecordBytes + 32 ||
          bytes > maxGenerationBytes ||
          !seen.add(jsonEncode([record.box, record.recordKey]))) {
        throw const FormatException('Invalid or duplicate vault record');
      }
      copies.add(
          VaultCipherRecord(record.box, record.recordKey, record.envelope));
    }
    copies.sort((a, b) {
      final boxOrder = a.box.compareTo(b.box);
      return boxOrder == 0 ? a.recordKey.compareTo(b.recordKey) : boxOrder;
    });
    return copies;
  }

  Uint8List _manifestBytes(String generation, List<VaultCipherRecord> records) {
    return Uint8List.fromList(utf8.encode(jsonEncode([
      'BlackoutKit/manifest/v3',
      generation,
      for (final record in records)
        [
          record.box,
          record.recordKey,
          sha256.convert(record.envelope).toString()
        ],
    ])));
  }

  Future<void> _verifyRecords(
      List<int> key, List<VaultCipherRecord> records) async {
    for (final record in records) {
      await _codec.open(
          key: key,
          box: record.box,
          recordKey: record.recordKey,
          envelope: record.envelope);
    }
  }

  Future<Uint8List> sealManifest({
    required List<int> key,
    required String generation,
    required List<VaultCipherRecord> records,
  }) async {
    _validateGeneration(generation);
    final snapshot = _snapshot(records);
    final keyCopy = _copyKey(key);
    try {
      await _verifyRecords(keyCopy, snapshot);
      return await _codec.seal(
        key: keyCopy,
        box: 'manifest',
        recordKey: generation,
        plaintext: _manifestBytes(generation, snapshot),
      );
    } finally {
      keyCopy.fillRange(0, keyCopy.length, 0);
    }
  }

  Future<void> _verifyManifest(List<int> key, String generation,
      List<VaultCipherRecord> records, Uint8List manifest) async {
    final actual = await _codec.open(
        key: key, box: 'manifest', recordKey: generation, envelope: manifest);
    final expected = _manifestBytes(generation, records);
    // The manifest consists only of identifiers and ciphertext hashes.
    if (actual.length != expected.length ||
        !actual.asMap().entries.every((e) => e.value == expected[e.key])) {
      throw const FormatException('Vault manifest mismatch');
    }
    await _verifyRecords(key, records);
  }

  /// Issue a marker only after validating the entire supplied readback.
  /// The caller remains responsible for flush/reopen and durable publication.
  Future<Uint8List> sealCommit({
    required List<int> key,
    required String generation,
    required List<VaultCipherRecord> records,
    required Uint8List manifest,
  }) async {
    _validateGeneration(generation);
    final snapshot = _snapshot(records);
    final manifestCopy = _copyMetadata(manifest);
    final keyCopy = _copyKey(key);
    try {
      await _verifyManifest(keyCopy, generation, snapshot, manifestCopy);
      return await _codec.seal(
        key: keyCopy,
        box: 'commit',
        recordKey: generation,
        plaintext: Uint8List.fromList(sha256.convert(manifestCopy).bytes),
      );
    } finally {
      keyCopy.fillRange(0, keyCopy.length, 0);
    }
  }

  /// Classify one expected generation. Never infer authority from timestamps,
  /// and never downgrade an invalid committed generation to staged or absent.
  Future<VaultGenerationState> inspect({
    required List<int> key,
    required String generation,
    required List<VaultCipherRecord> records,
    Uint8List? manifest,
    Uint8List? commit,
    bool expectCommitted = false,
  }) async {
    Uint8List? keyCopy;
    try {
      keyCopy = _copyKey(key);
      _validateGeneration(generation);
      final snapshot = _snapshot(records);
      if (manifest == null) {
        return !expectCommitted && snapshot.isEmpty && commit == null
            ? VaultGenerationState.absent
            : VaultGenerationState.locked;
      }
      final manifestCopy = _copyMetadata(manifest);
      final commitCopy = commit == null ? null : _copyMetadata(commit);
      await _verifyManifest(keyCopy, generation, snapshot, manifestCopy);
      if (commitCopy == null) {
        return expectCommitted
            ? VaultGenerationState.locked
            : VaultGenerationState.staged;
      }
      final actual = await _codec.open(
          key: keyCopy,
          box: 'commit',
          recordKey: generation,
          envelope: commitCopy);
      final expected = sha256.convert(manifestCopy).bytes;
      if (actual.length != expected.length ||
          !actual.asMap().entries.every((e) => e.value == expected[e.key])) {
        return VaultGenerationState.locked;
      }
      return VaultGenerationState.committed;
    } catch (_) {
      return VaultGenerationState.locked;
    } finally {
      if (keyCopy != null) keyCopy.fillRange(0, keyCopy.length, 0);
    }
  }
}
