import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tool.compare_go_candidate_replicas import compare
from tool.build_pinned_go_engines import ENGINES, PATCHED_GO_VERSION


class CandidateReplicaTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.engine = "tun2socks"
        self.elf = {"androidApi": 24}
        for replica in (1, 2):
            folder = self.root / f"native-go-{self.engine}-{replica}"
            artifacts = []
            for abi in ("arm64-v8a", "armeabi-v7a"):
                binary = folder / abi / "libtun2socks.so"
                binary.parent.mkdir(parents=True)
                data = abi.encode()
                binary.write_bytes(data)
                artifacts.append({"abi": abi, "sha256": hashlib.sha256(data).hexdigest(),
                                  "bytes": len(data), "elf": self.elf})
            evidence = {"go": f"go version {PATCHED_GO_VERSION} linux/amd64",
                        "pin": ENGINES[self.engine], "ndk": "fixture",
                        "go_sha256": "fixture", "clang_sha256": "fixture",
                        "candidate_snapshot_sha256": {"go.mod": "fixture"},
                        "osv": {"findings": []}, "artifacts": artifacts}
            (folder / "PROVENANCE.json").write_text(json.dumps(evidence))
        mock = patch("tool.compare_go_candidate_replicas.validate", return_value=self.elf)
        mock.start()
        self.addCleanup(mock.stop)

    def test_identical_replicas(self):
        self.assertEqual(len(compare(self.root, self.engine)["sha256"]), 2)

    def test_tampered_artifact(self):
        path = self.root / "native-go-tun2socks-2/arm64-v8a/libtun2socks.so"
        path.write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "evidence mismatch"):
            compare(self.root, self.engine)

    def test_different_verified_replicas(self):
        folder = self.root / "native-go-tun2socks-2"
        data = b"other"
        (folder / "arm64-v8a/libtun2socks.so").write_bytes(data)
        path = folder / "PROVENANCE.json"
        evidence = json.loads(path.read_text())
        evidence["artifacts"][0].update(sha256=hashlib.sha256(data).hexdigest(), bytes=len(data))
        path.write_text(json.dumps(evidence))
        with self.assertRaisesRegex(ValueError, "hashes differ"):
            compare(self.root, self.engine)
