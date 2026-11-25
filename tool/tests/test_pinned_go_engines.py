import json
from pathlib import Path
import unittest

from tool.build_pinned_go_engines import (
    ENGINES, decode_module_downloads, dependency_diff, validate_lock,
    verify_build_info, verify_source,
)


class PinnedGoEngineTests(unittest.TestCase):
    def setUp(self):
        self.pin = ENGINES["tun2socks"]
        self.record = {
            "Path": self.pin["module"],
            "Version": self.pin["version"],
            "Sum": self.pin["sum"],
            "GoModSum": self.pin["mod_sum"],
            "Origin": {"Hash": self.pin["commit"]},
        }

    def test_matching_pin(self):
        verify_source(self.record, self.pin)

    def test_source_metadata_mismatch(self):
        for key in ("Path", "Version", "Sum", "GoModSum", "Origin"):
            with self.subTest(key=key), self.assertRaises(ValueError):
                verify_source(self.record | {key: {"Hash": "wrong"} if key == "Origin" else "wrong"}, self.pin)

    def test_missing_origin_does_not_waive_checksum(self):
        del self.record["Origin"]
        verify_source(self.record, self.pin)
        self.record["Sum"] = "wrong"
        with self.assertRaises(ValueError):
            verify_source(self.record, self.pin)

    def test_build_target_and_module_must_match(self):
        module = "\tmod\t" + self.pin["module"] + "\t" + self.pin["version"] + "\t" + self.pin["sum"]
        lines = [module, "\tbuild\tGOOS=android", "\tbuild\tGOARCH=arm64",
                 "\tbuild\tCGO_ENABLED=1", "\tbuild\t-trimpath=true"]
        verify_build_info("\n".join(lines), module, "arm64")
        for index in range(len(lines)):
            with self.subTest(index=index), self.assertRaises(ValueError):
                verify_build_info("\n".join(lines[:index] + lines[index + 1:]), module, "arm64")
        with self.assertRaises(ValueError):
            verify_build_info("\n".join(lines), module, "arm")

    def test_dependency_diff_detects_version_checksum_and_membership_changes(self):
        old = "\tdep\ta\tv1.0.0\th1:old\n\tdep\tb\tv1.0.0\th1:same\n\tdep\tc\tv1.0.0\th1:old"
        new = "\tdep\ta\tv1.0.0\th1:new\n\tdep\tb\tv1.1.0\th1:new\n\tdep\td\tv1.0.0\th1:new"
        changes = dependency_diff(old, new)
        self.assertEqual([item["module"] for item in changes], ["a", "b", "c", "d"])
        self.assertIsNone(changes[2]["candidate"])
        self.assertIsNone(changes[3]["baseline"])
        self.assertEqual(dependency_diff(old, old), [])

    def test_replacement_and_invalid_metadata(self):
        old = "\tdep\ta\tv1.0.0\n\t=>\tb\tv1.0.0\th1:old"
        new = old.replace("h1:old", "h1:new")
        self.assertEqual(len(dependency_diff(old, new)), 1)
        for invalid in ("", old + "\n" + old, "\t=>\tb\tv1.0.0"):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                dependency_diff(old, invalid)

    def test_tracked_locks_have_pinned_main_and_unique_modules(self):
        root = Path(__file__).resolve().parents[2]
        for engine, expected in (("tun2socks", 22), ("singbox", 81)):
            with self.subTest(engine=engine):
                lock = json.loads((root / "tool/go_engine_locks" / (engine + ".json")).read_text())
                records = validate_lock(lock, engine, ENGINES[engine])
                self.assertEqual(len(records), expected)
                self.assertEqual(set(lock["baseline_sha256"]), {"arm64-v8a", "armeabi-v7a"})
                self.assertTrue(all(len(value) == 64 for value in lock["baseline_sha256"].values()))

    def test_lock_rejects_duplicate_and_mismatched_main(self):
        record = {"path": self.pin["module"], "version": self.pin["version"],
                  "sum": self.pin["sum"], "mod_sum": self.pin["mod_sum"]}
        lock = {"schema": 1, "engine": "tun2socks", "modules": [record]}
        validate_lock(lock, "tun2socks", self.pin)
        for bad in ([record, record], [record | {"sum": "h1:wrong"}],
                    [record, record | {"path": "-unexpected"}]):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                validate_lock(lock | {"modules": bad}, "tun2socks", self.pin)

    def test_module_download_parser_rejects_duplicate_or_error(self):
        good = '{"Path":"one","Version":"v1.0.0"}'
        self.assertEqual(set(decode_module_downloads(good + '\n{"Path":"two"}')), {"one", "two"})
        for bad in (good + good, '{"Path":"one","Error":"missing"}'):
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                decode_module_downloads(bad)
