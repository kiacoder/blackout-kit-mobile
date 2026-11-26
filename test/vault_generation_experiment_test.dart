import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../tool/vault_generation_experiment.dart';
import '../tool/vault_record_experiment.dart';

void main() {
  final recordsCodec = VaultRecordExperiment();
  final codec = VaultGenerationExperiment();
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  const generation = '0123456789abcdef0123456789abcdef';
  const otherGeneration = 'abcdef0123456789abcdef0123456789';
  late List<VaultCipherRecord> records;
  late Uint8List manifest;
  late Uint8List commit;

  Future<VaultCipherRecord> record(String box, String id, String value) async =>
      VaultCipherRecord(
        box,
        id,
        await recordsCodec.seal(
            key: key,
            box: box,
            recordKey: id,
            plaintext: Uint8List.fromList(utf8.encode(value))),
      );

  setUp(() async {
    records = [
      await record('configs', 'a', 'synthetic config'),
      await record('sources', 'a', 'synthetic source'),
      await record('test_results', 'b', 'synthetic result'),
    ];
    manifest = await codec.sealManifest(
        key: key, generation: generation, records: records);
    commit = await codec.sealCommit(
        key: key, generation: generation, records: records, manifest: manifest);
  });

  Future<VaultGenerationState> inspect({
    List<VaultCipherRecord>? withRecords,
    Uint8List? withManifest,
    Uint8List? withCommit,
    String withGeneration = generation,
    List<int>? withKey,
    bool expectCommitted = false,
  }) =>
      codec.inspect(
          key: withKey ?? key,
          generation: withGeneration,
          records: withRecords ?? records,
          manifest: withManifest,
          commit: withCommit,
          expectCommitted: expectCommitted);

  test('valid staged generation is not committed; ordering is irrelevant',
      () async {
    expect(await inspect(withManifest: manifest), VaultGenerationState.staged);
    expect(
        await inspect(
            withRecords: records.reversed.toList(),
            withManifest: manifest,
            withCommit: commit),
        VaultGenerationState.committed);
  });

  test('missing data or partial staging is not authoritative', () async {
    expect(await inspect(withRecords: []), VaultGenerationState.absent);
    expect(await inspect(), VaultGenerationState.locked);
    expect(await inspect(withCommit: commit), VaultGenerationState.locked);
    expect(await inspect(withRecords: [], expectCommitted: true),
        VaultGenerationState.locked);
    expect(await inspect(withManifest: manifest, expectCommitted: true),
        VaultGenerationState.locked);
  });

  test('record omission, addition and duplicates are rejected', () async {
    final extra = await record('configs', 'extra', 'synthetic');
    for (final changed in [
      records.sublist(1),
      [...records, extra],
      [...records, records.first],
    ]) {
      expect(
          await inspect(
              withRecords: changed, withManifest: manifest, withCommit: commit),
          VaultGenerationState.locked);
    }
  });

  test('valid older ciphertext for the same record does not match manifest',
      () async {
    final old = await record('configs', 'a', 'previous value');
    expect(
        await inspect(
            withRecords: [old, ...records.skip(1)],
            withManifest: manifest,
            withCommit: commit),
        VaultGenerationState.locked);
  });

  test('marker binds the exact manifest, even if replacement is authentic',
      () async {
    final other = await codec.sealManifest(
        key: key, generation: generation, records: records);
    expect(await inspect(withManifest: other), VaultGenerationState.staged);
    expect(await inspect(withManifest: other, withCommit: commit),
        VaultGenerationState.locked);
  });

  test('tampered metadata, wrong generation and wrong key fail closed',
      () async {
    final brokenManifest = Uint8List.fromList(manifest)..[20] ^= 1;
    final brokenCommit = Uint8List.fromList(commit)..[20] ^= 1;
    expect(await inspect(withManifest: brokenManifest, withCommit: commit),
        VaultGenerationState.locked);
    expect(await inspect(withManifest: manifest, withCommit: brokenCommit),
        VaultGenerationState.locked);
    expect(
        await inspect(
            withManifest: manifest,
            withCommit: commit,
            withGeneration: otherGeneration),
        VaultGenerationState.locked);
    expect(
        await inspect(
            withManifest: manifest, withCommit: commit, withKey: Uint8List(32)),
        VaultGenerationState.locked);
    expect(
        await inspect(
            withManifest: manifest,
            withCommit: commit,
            withKey: [256, ...key.skip(1)]),
        VaultGenerationState.locked);
  });

  test('cannot issue commit for invalid record readback', () async {
    await expectLater(
        codec.sealCommit(
            key: key,
            generation: generation,
            records: records.sublist(1),
            manifest: manifest),
        throwsFormatException);
  });

  test('empty library requires its own authenticated manifest and commit',
      () async {
    final empty =
        await codec.sealManifest(key: key, generation: generation, records: []);
    final marker = await codec.sealCommit(
        key: key, generation: generation, records: [], manifest: empty);
    expect(
        await inspect(withRecords: [], withManifest: empty, withCommit: marker),
        VaultGenerationState.committed);
    expect(await inspect(withRecords: [], withManifest: empty),
        VaultGenerationState.staged);
  });
}
