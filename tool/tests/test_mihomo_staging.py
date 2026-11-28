import unittest

from tool.stage_mihomo import GO, PIN, VERSION, check_build_info


def metadata(arch="arm64"):
    return "\n".join([
        "libmihomo.so: " + GO,
        "\tpath\tgithub.com/metacubex/mihomo",
        "\tmod\tgithub.com/metacubex/mihomo\t" + VERSION + "\t",
        "\tbuild\tGOOS=android",
        "\tbuild\tGOARCH=" + arch,
        "\tbuild\tCGO_ENABLED=1",
        "\tbuild\t-trimpath=true",
        "\tbuild\tvcs.revision=" + PIN,
        "\tbuild\tvcs.modified=false",
    ])


class MihomoStagingTests(unittest.TestCase):
    def test_both_abis(self):
        for arch in ("arm64", "arm"):
            check_build_info(metadata(arch), arch)

    def test_reject_wrong_identity(self):
        for bad in (
            "",
            metadata().replace(PIN, "unexpected"),
            metadata().replace(VERSION, "v0.0.0"),
            metadata().replace(GO, "go1.0"),
            metadata().replace("modified=false", "modified=true"),
            metadata().replace("GOOS=android", "GOOS=linux"),
            metadata().replace("CGO_ENABLED=1", "CGO_ENABLED=0"),
            metadata("arm"),
        ):
            with self.subTest(bad=bad):
                with self.assertRaises(ValueError):
                    check_build_info(bad, "arm64")


if __name__ == "__main__":
    unittest.main()
