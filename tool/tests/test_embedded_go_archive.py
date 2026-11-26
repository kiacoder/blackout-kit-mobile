import unittest

from tool.audit_embedded_go_archive import inspect_info


class EmbeddedGoArchiveTests(unittest.TestCase):
    def setUp(self):
        checksum = "h1:" + "A" * 43 + "="
        self.info = "\n".join([
            "fixture.so: go1.27.0",
            "\tmod\tbkcores\t(devel)\t",
            "\tdep\tgithub.com/example/module\tv1.0.0\t" + checksum,
            "\tdep\tgithub.com/example/replaced\tv1.0.0",
            "\t=>\tgithub.com/example/replaced\tv1.1.0\t" + checksum,
            "\tdep\tgithub.com/example/local\tv0.0.0-00010101000000-000000000000",
            "\t=>\t../local\t(devel)\t",
            "\tbuild\tGOOS=android",
            "\tbuild\tGOARCH=arm64",
            "\tbuild\tCGO_ENABLED=1",
        ])

    def test_effective_replacements_and_unknown_sources(self):
        compiler, _, known, unknown = inspect_info(self.info, "arm64-v8a")
        self.assertEqual(compiler, "go1.27.0")
        self.assertEqual(known, {
            ("stdlib", "1.27.0"), ("github.com/example/module", "v1.0.0"),
            ("github.com/example/replaced", "v1.1.0"),
        })
        self.assertEqual({item["module"] for item in unknown}, {"bkcores", "github.com/example/local"})

    def test_wrong_target_fails(self):
        with self.assertRaisesRegex(ValueError, "target"):
            inspect_info(self.info, "armeabi-v7a")

    def test_missing_main_identity_fails(self):
        with self.assertRaisesRegex(ValueError, "main module"):
            inspect_info(self.info.replace("\tmod\t", "\tother\t"), "arm64-v8a")
