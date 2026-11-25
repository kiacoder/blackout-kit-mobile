import json
from pathlib import Path
import tempfile
import unittest

from tool.audit_go_engine_locks import audit, load_queries


class GoLockAuditTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        folder = self.root / "tool/go_engine_locks"
        folder.mkdir(parents=True)
        for engine, names in (("singbox", ["a", "b"]), ("tun2socks", ["a", "c"])):
            (folder / (engine + ".json")).write_text(json.dumps({
                "schema": 1, "engine": engine,
                "modules": [{"path": name, "version": "v1.0.0"} for name in names],
            }))

    def test_deduplication_and_attribution(self):
        def fetch(queries):
            self.assertEqual(len(queries), 3)
            return {"results": [{"vulns": [{"id": "TEST-1"}]}, {}, {}]}
        report = audit(self.root, fetch)
        self.assertEqual(report["unique_module_versions"], 3)
        self.assertEqual(report["findings"][0]["engines"], ["singbox", "tun2socks"])
        self.assertEqual(report["findings"][0]["module"], "a")
        self.assertEqual(len(report["lock_sha256"]), 2)

    def test_empty_results_are_valid(self):
        report = audit(self.root, lambda queries: {"results": [{} for _ in queries]})
        self.assertEqual(report["findings"], [])

    def test_incomplete_or_paginated_result_fails_closed(self):
        for response in ({"results": []}, {},
                         {"results": [{"next_page_token": "next"}, {}, {}]},
                         {"results": [{"vulns": None}, {}, {}]}):
            with self.subTest(response=response), self.assertRaises(ValueError):
                audit(self.root, lambda _: response)

    def test_duplicate_module_rejected(self):
        file = self.root / "tool/go_engine_locks/singbox.json"
        data = json.loads(file.read_text())
        data["modules"].append(data["modules"][0])
        file.write_text(json.dumps(data))
        with self.assertRaises(ValueError):
            load_queries(self.root)
