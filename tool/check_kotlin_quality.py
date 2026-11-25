"""Pinned standalone Kotlin quality checks; independent of the Android toolchain."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".cache" / "kotlin-quality"
MAVEN = "https://repo.maven.apache.org/maven2/"
TOOLS = {
    "ktlint": (
        "com/pinterest/ktlint/ktlint-cli/1.5.0/ktlint-cli-1.5.0-all.jar",
        "a27854622198800f50971a049dcdba38f2105d47e7e7258786c7d28045c5735d",
    ),
    "detekt": (
        "io/gitlab/arturbosch/detekt/detekt-cli/1.23.8/detekt-cli-1.23.8-all.jar",
        "3afe89a11120303c73c9bdda3d8fe558dd9070a6937d27819ddc04b275381245",
    ),
}
# Strict scope expands as existing findings are fixed, not silently suppressed.
GATED = [
    "android/app/src/main/kotlin/com/blackoutkit/vpn/OneShotCallbackSlot.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/GoRuntimeAdmission.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/SubprocessLifecycle.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/VpnSessionExecutor.kt",
    "android/app/src/main/kotlin/com/wireguard/android/backend/GoBackend.kt",
    "android/app/src/main/kotlin/org/amnezia/awg/GoBackend.kt",
    "android/app/src/test/kotlin/com/blackoutkit/vpn/GoRuntimeAdmissionTest.kt",
    "android/app/src/test/kotlin/com/blackoutkit/vpn/NativeTunnelConfigTest.kt",
    "android/app/src/test/kotlin/com/blackoutkit/vpn/OneShotCallbackSlotTest.kt",
    "android/app/src/test/kotlin/com/blackoutkit/vpn/SubprocessLifecycleTest.kt",
    "android/app/src/test/kotlin/com/blackoutkit/vpn/VpnSessionExecutorTest.kt",
    "tool/kotlin/android/os/Build.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/BlackoutCoreEngine.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/LocalSocksReadiness.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/NativeChildStop.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/NativeTunnelConfig.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/NativeTunnelEngine.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/NativeTunnelLifecycle.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/ProcessCompat.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/EngineCommands.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/MainActivity.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/NetworkPlugin.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/UpdatePlugin.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/BoundedImport.kt",
    "android/app/src/test/kotlin/com/blackoutkit/vpn/BoundedImportTest.kt",
    "tool/kotlin/com/blackoutkit/vpn/EngineHostTests.kt",
    "tool/kotlin/com/blackoutkit/vpn/NativeTunnelConfigTests.kt",
    "tool/kotlin/com/blackoutkit/vpn/NativeTunnelLifecycleTests.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/SiteProbeRunner.kt",
    "android/app/src/test/kotlin/com/blackoutkit/vpn/SiteProbeRunnerTest.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/EngineRunner.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/LibboxEngine.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/XrayEngine.kt",
    "android/app/src/test/kotlin/com/blackoutkit/vpn/EmbeddedCoreOwnerTest.kt",
    "android/app/src/main/kotlin/com/blackoutkit/vpn/TunnelCleanup.kt",
    "android/app/src/test/kotlin/com/blackoutkit/vpn/TunnelCleanupTest.kt",
]


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def jar(name):
    url, expected = TOOLS[name]
    CACHE.mkdir(parents=True, exist_ok=True)
    path = CACHE / (name + ".jar")
    if not path.exists():
        temp = path.with_suffix(".part")
        try:
            with urllib.request.urlopen(MAVEN + url, timeout=60) as response, temp.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
            if digest(temp) != expected:
                raise RuntimeError(f"{name} download checksum mismatch")
            temp.replace(path)
        finally:
            temp.unlink(missing_ok=True)
    if digest(path) != expected:
        raise RuntimeError(f"{name} cached checksum mismatch")
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit", action="store_true", help="Scan all Kotlin files; fail on findings")
    args = parser.parse_args()
    java = str(Path(os.environ["JAVA_HOME"]) / "bin" / "java") if "JAVA_HOME" in os.environ else "java"
    for file in GATED:
        if not (ROOT / file).is_file():
            raise RuntimeError(f"Missing gated source: {file}")
    lint_inputs = ["android/app/src/**/*.kt", "tool/kotlin/**/*.kt"]
    detekt_inputs = ["android/app/src", "tool/kotlin"] if args.audit else GATED
    lint = subprocess.run(
        [java, "-jar", str(jar("ktlint")), "--relative", *lint_inputs],
        cwd=ROOT, check=False,
    )
    detekt = subprocess.run(
        [java, "-jar", str(jar("detekt")), "--input", ",".join(detekt_inputs),
         "--base-path", ".", "--build-upon-default-config"],
        cwd=ROOT, check=False,
    )
    return 0 if lint.returncode == detekt.returncode == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
