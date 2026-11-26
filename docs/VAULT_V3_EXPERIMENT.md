# Authenticated vault v3 experiment

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

The prototype only authenticates individual records. It does not
authenticate a complete library, detect same-record replay, detect
record deletion or rollback, provide a durable storage transaction,
or implement production key management. Secure erasure on flash and
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
