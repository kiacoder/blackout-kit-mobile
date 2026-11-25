"""Pinned standalone Kotlin quality checks; independent of the Android toolchain."""
import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import time
import urllib.error
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
# All production and test Kotlin sources, with no baseline or partial allowlist.
DETEKT_INPUTS = ["android/app/src", "tool/kotlin"]
DOWNLOAD_ATTEMPTS = 6
RETRYABLE_HTTP_STATUS = {429, 500, 502, 503, 504}
MAX_RETRY_DELAY = 60


def retry_delay(attempt, retry_after=None):
    delay = min(MAX_RETRY_DELAY, 5 * 2**attempt)
    if retry_after and retry_after.isdecimal():
        # Bound server-provided delays so the CI job remains finite.
        delay = max(delay, min(MAX_RETRY_DELAY, int(retry_after)))
    return delay


def download(url, target):
    for attempt in range(DOWNLOAD_ATTEMPTS):
        try:
            with urllib.request.urlopen(url, timeout=60) as response, target.open("wb") as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
            return
        except urllib.error.HTTPError as error:
            if error.code not in RETRYABLE_HTTP_STATUS or attempt + 1 == DOWNLOAD_ATTEMPTS:
                raise
            delay = retry_delay(attempt, error.headers.get("Retry-After") if error.headers else None)
            error.close()
        except (urllib.error.URLError, TimeoutError):
            if attempt + 1 == DOWNLOAD_ATTEMPTS:
                raise
            delay = retry_delay(attempt)
        print(f"Transient Kotlin tool download failure; retrying in {delay}s.", flush=True)
        time.sleep(delay)


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
            download(MAVEN + url, temp)
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
    parser.add_argument("--audit", action="store_true", help="Compatibility alias; full audit is always enforced")
    parser.parse_args()
    java = str(Path(os.environ["JAVA_HOME"]) / "bin" / "java") if "JAVA_HOME" in os.environ else "java"
    # Explicit paths prevent ktlint's recursive glob matching from including
    # generated fixture projects under .cache.
    lint_inputs = sorted(
        path.relative_to(ROOT).as_posix()
        for directory in DETEKT_INPUTS
        for path in (ROOT / directory).rglob("*.kt")
        if path.is_file()
    )
    if not lint_inputs:
        raise RuntimeError("No Kotlin sources found")
    detekt_inputs = DETEKT_INPUTS
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
