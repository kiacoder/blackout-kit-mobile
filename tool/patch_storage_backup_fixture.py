#!/usr/bin/env python3
"""Experiment-only v10.3.4 correction for upstream issue #1293.

Do not apply to a shared pub cache or to the shipping application.
"""
import argparse
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path("hosted/pub.dev/flutter_secure_storage-10.3.4/android/src/main/java/com/it_nomads/fluttersecurestorage/FlutterSecureStorage.java")
UPSTREAM_SHA256 = "15319336c69dfcfe10b359ea01f317bf7a0f51882c19de61baeb2b073fb0ab47"
OLD_CALL = "if (canSkipMarkerlessMigration()) {"
OLD_METHOD = "private boolean canSkipMarkerlessMigration() {"
ANCHOR = """        try {
            if (storageCipherFactory.getCurrentKeyCipher(context).getCipher(context) != null) {"""
GUARD = """        try {
            // ESP key names are encrypted; an absent plaintext prefix is not
            // evidence of a fresh install when its legacy keysets remain.
            SharedPreferences legacyPrefs = context.getSharedPreferences(
                    config.getEffectiveDataPrefsName(), Context.MODE_PRIVATE);
            if (config.shouldMigrateWithBackup()
                    && !getEncryptedPrefsMigrated(configSource)
                    && (legacyPrefs.contains("__androidx_security_crypto_encrypted_prefs_key_keyset__")
                        || legacyPrefs.contains("__androidx_security_crypto_encrypted_prefs_value_keyset__"))) {
                return false;
            }
            if (storageCipherFactory.getCurrentKeyCipher(context).getCipher(context) != null) {"""


def patched_source(raw):
    if hashlib.sha256(raw).hexdigest() != UPSTREAM_SHA256:
        raise ValueError("Unexpected upstream Java bytes; review exact source first")
    source = raw.decode("utf-8")
    for old, new in (
        (OLD_CALL, "if (canSkipMarkerlessMigration(configSource)) {"),
        (OLD_METHOD, "private boolean canSkipMarkerlessMigration(NamespacedConfigSource configSource) {"),
        (ANCHOR, GUARD),
    ):
        if source.count(old) != 1:
            raise ValueError("Unexpected migration patch anchor")
        source = source.replace(old, new)
    return source.encode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pub-cache", type=Path, required=True)
    args = parser.parse_args()
    cache = args.pub_cache.resolve()
    if cache != (ROOT / ".cache/storage-backup-pub").resolve():
        raise ValueError("Refusing to modify a non-fixture pub cache")
    target = cache / SOURCE
    if not target.resolve().is_relative_to(cache):
        raise ValueError("Refusing source outside fixture cache")
    raw = target.read_bytes()
    changed = patched_source(raw)
    target.write_bytes(changed)
    print("Fixture-only migration patch SHA256:", hashlib.sha256(changed).hexdigest())


if __name__ == "__main__":
    main()
