# Authenticated vault v3 experiment

Research or checkpoint record; preserved at its original scope. For the published version and current acceptance limits, see [CURRENT_STATUS.md](../CURRENT_STATUS.md).

Status: development-only proof of concept, not a shipping storage format.

## Format and evidence

The current Hive v2 format uses AES-CBC without cryptographic record
authentication. The isolated tool/vault_record_experiment.dart prototype
uses AES-256-GCM from cryptography 2.9.0 (Apache-2.0). The package is
pinned as a development dependency. Its official archive SHA-256 was
verified against pub.dev, and the existing lockfile resolved offline
with no other package version changes.

Envelope: four bytes BKV3, a fresh 12-byte random nonce, ciphertext,
and a 16-byte authentication tag. The associated data is UTF-8 JSON of
["BlackoutKit/vault/v3", boxName, recordKey]. A record is bound to its
logical box and key. The codec requires a separate 32-byte v3 key;
do not reuse the Hive v2 key. Maximum plaintext size is 8 MiB and
record keys are bounded to 1024 UTF-8 bytes.

Seven focused tests cover binary/empty records, an independent Python
AESGCM interoperability fixture, nonce variation, tampering of nonce,
ciphertext and tag, wrong key, wrong record/box context, malformed and
oversized envelopes, and invalid inputs. Nonce sampling is not a proof
of uniqueness. No independent security audit is claimed.

## Authenticated generation experiment

The development-only generation verifier in
tool/vault_generation_experiment.dart authenticates the sorted inventory of
logical box, record key and SHA-256 of each encrypted record. It rejects
duplicate identities, verifies each record's AEAD, and binds the manifest
to a caller-supplied expected 128-bit generation identifier (32 lowercase
hex characters). The reserved metadata contexts are "manifest" and "commit";
each uses the generation identifier as its record key. The commit envelope
authenticates the digest of the exact encrypted manifest. It is issued only
after verifying the supplied record readback.

Recovery classification is explicit: absent, verified staged, verified
committed, or locked. Incomplete and inconsistent data fail closed. When
the caller independently knows that the generation was committed, a missing
marker or missing generation is locked rather than staged or absent.

Eight additional tests cover staging versus commit, partial state, missing
marker, extra/missing/duplicate records, replay of an older individual record,
replacement of a manifest, altered metadata, wrong generation/key, invalid
readback and an authenticated empty library. Bounds are 10,000 records and
64 MiB of encrypted record data; the existing 8 MiB envelope payload limit
also applies to metadata. These are experimental limits, not product limits.

This verifier does not itself persist or select the authoritative generation.
A trusted external generation/commit expectation, durable publication,
exclusive ownership and rollback policy remain necessary. It is not a
filesystem crash-recovery test and must not be activated in the app.

## Migration requirements before production activation

1. Preserve the existing v2 library and secure-storage key. Use a
   distinct versioned key slot, validate persistence and never generate
   a replacement for an existing unreadable v3 generation.
2. Establish exclusive storage ownership. Preflight all existing
   generations, supported record types, capacity and file permissions.
3. Write a separate staging generation with bounded records, no
   plaintext export files, authenticated manifest and stable record keys.
4. Flush, close, reopen and verify every record and manifest against
   the source before marking the new generation committed.
5. Use a durable, independently tested commit marker and explicit
   recovery state machine. After an interruption, distinguish a
   staged copy from an authoritative generation; never pick the
   newest timestamp or silently discard a conflicting copy.
6. Verify the persisted key again before enabling writes. Define
   deletion/retention of v2 only after recovery and rollback policies
   are tested. An old application must not overwrite a migrated
   library or make a stale generation authoritative.
7. Test failure at every durable boundary, low space, malformed
   legacy values, key loss, interrupted writes, skipped upgrades,
   Android API 24/34 and real devices; also test iOS independently.

## Explicit limitations

The prototype authenticates records and an exact generation inventory. It
detects record deletion and same-record replay relative to a verified
manifest, but cannot detect replay or deletion of an entire generation
without independently trusted state. It does not provide a durable storage
transaction or production key management. Secure erasure on flash and
protection against a compromised running application are not guaranteed.
The underlying Dart implementation and its side-channel characteristics
need review. No claim of a cryptographic audit or resolved MobSF finding.

Neither production ConfigService nor SecureVault is wired to this
experiment. Existing v1/v2 files, cipher, key and secure-storage plugin
are unchanged. The experimental format must not be used for real user
credentials until its migration and security gates have been satisfied.

References:
- https://pub.dev/packages/cryptography/versions/2.9.0
- https://pub.dev/documentation/cryptography/latest/cryptography/AesGcm-class.html
