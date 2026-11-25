#!/usr/bin/env python3
"""Build isolated Android candidates from pinned Go modules; never stage into app."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

if __package__:
    from .check_android_artifact import validate
else:
    from check_android_artifact import validate

ROOT = Path(__file__).resolve().parents[1]
GO_VERSION = "go1.27.0"
NDK_VERSION = "28.2.13676358"
ENGINES = {
    "tun2socks": {
        "module": "github.com/xjasonlyu/tun2socks/v2",
        "package": "github.com/xjasonlyu/tun2socks/v2",
        "version": "v2.7.0",
        "sum": "h1:fYEN0Q1sSanuoID8xvUTsMODbKLJJH/J5ywYoMRxIPw=",
        "mod_sum": "h1:XHgJ3wbs63mZxGbJawt6jjNX65aPDl+Qhn2ePPEE4KI=",
        "commit": "dda1b1058db86dd0ef40d1b007de0ce86cf16a46",
        "tags": "",
        "executable": "tun2socks",
    },
    "singbox": {
        "module": "github.com/sagernet/sing-box",
        "package": "github.com/sagernet/sing-box/cmd/sing-box",
        "version": "v1.14.2",
        "sum": "h1:uZX7iz70o7lzoltR6sElMYP7kI7PVf23r4X0HQSozXM=",
        "mod_sum": "h1:O4q0spxb+xwV/p9HYR+Es1cMjK3bBvYl6k08V9rSpwU=",
        "commit": "af6e64c3b69e6132ebaee0e1a3d24e93903f6709",
        "tags": "with_quic,with_wireguard,with_utls,with_clash_api,with_gvisor",
        "executable": "sing-box",
    },
}
ABIS = {
    "arm64-v8a": ("arm64", "aarch64-linux-android24"),
    "armeabi-v7a": ("arm", "armv7a-linux-androideabi24"),
}


def run(args, env, cwd, capture=False):
    return subprocess.run(args, env=env, cwd=cwd, check=True, text=True,
                          stdout=subprocess.PIPE if capture else None).stdout


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def verify_source(record, pin):
    if (record.get("Path"), record.get("Version"), record.get("Sum"),
            record.get("GoModSum")) != (
            pin["module"], pin["version"], pin["sum"], pin["mod_sum"]):
        raise ValueError("Pinned module metadata mismatch")
    # Some module proxies omit origin metadata; the pinned module sums
    # are mandatory regardless. Evidence records whether origin was supplied.
    origin = record.get("Origin", {})
    if origin and origin.get("Hash") != pin["commit"]:
        raise ValueError("Module origin revision mismatch")


def verify_build_info(info, module_line, arch):
    lines = set(info.splitlines())
    required = {module_line, "\tbuild\tGOOS=android",
                "\tbuild\tGOARCH=" + arch, "\tbuild\tCGO_ENABLED=1",
                "\tbuild\t-trimpath=true"}
    if not required <= lines:
        raise ValueError("Built artifact has unexpected module or target identity")


def build(args):
    pin = ENGINES[args.engine]
    cache = ROOT / ".cache"
    cache.mkdir(exist_ok=True)
    out = args.output.resolve()
    if cache.resolve() not in out.parents or out.exists():
        raise ValueError("Use a new output directory strictly inside .cache")
    ndk = args.ndk.resolve()
    properties = (ndk / "source.properties").read_text()
    if f"Pkg.Revision = {NDK_VERSION}" not in properties.splitlines():
        raise ValueError("Wrong NDK revision")
    host = "windows-x86_64" if os.name == "nt" else "linux-x86_64"
    clang = ndk / "toolchains/llvm/prebuilt" / host / "bin" / (
        "clang.exe" if os.name == "nt" else "clang")
    if not clang.is_file():
        raise ValueError("NDK clang missing")
    go = shutil.which("go")
    if not go:
        raise ValueError("Go executable missing")
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(("GO", "CGO_")) or key in ("CC", "CXX"):
            env.pop(key)
    env.update(GOENV="off", GOTOOLCHAIN="local", GOFLAGS="", GOWORK="off",
               GOPROXY="https://proxy.golang.org", GOSUMDB="sum.golang.org",
               GONOSUMDB="", GOPRIVATE="", GONOPROXY="", GOINSECURE="")
    version = run([go, "version"], env, ROOT, True).strip()
    if version.split()[2] != GO_VERSION:
        raise ValueError("Wrong Go version: " + version)
    if args.module_cache:
        env["GOMODCACHE"] = str(args.module_cache.resolve())
    with tempfile.TemporaryDirectory(prefix="go-engine-", dir=cache) as work:
        workspace = Path(work)
        env["GOPATH"] = str(workspace / "gopath")
        # Keep the module cache separate from the install output.
        if "GOMODCACHE" not in env:
            env["GOMODCACHE"] = str(workspace / "modules")
        spec = pin["module"] + "@" + pin["version"]
        metadata = json.loads(run([go, "mod", "download", "-json", spec],
                                  env, workspace, True))
        verify_source(metadata, pin)
        (workspace / "go.mod").write_text(
            "module blackout-rebuild-audit\n\ngo 1.27.0\n\nrequire "
            + pin["module"] + " " + pin["version"] + "\n", encoding="utf-8")
        # Download and verify the pinned source module, not just its cached hash.
        run([go, "mod", "download", spec], env, workspace)
        run([go, "mod", "verify"], env, workspace)
        staging = workspace / "output"
        staging.mkdir()
        evidence = {
            "status": "candidate-not-device-tested",
            "pin": pin, "go": version, "ndk": NDK_VERSION,
            "go_sha256": sha(Path(go)), "clang_sha256": sha(clang),
            "module_origin": metadata.get("Origin"),
            "artifacts": [],
        }
        for abi in args.abi or ABIS:
            arch, target = ABIS[abi]
            target_env = env | {
                "GOOS": "android", "GOARCH": arch, "CGO_ENABLED": "1",
                "CC": f'"{clang.as_posix()}" --target={target}',
            }
            target_env["GOARM" if arch == "arm" else "GOARM64"] = (
                "7" if arch == "arm" else "v8.0")
            command = [go, "install", "-trimpath", "-buildvcs=false",
                       "-buildmode=pie", "-ldflags=-s -w"]
            if pin["tags"]:
                command.append("-tags=" + pin["tags"])
            command.append(pin["package"] + "@" + pin["version"])
            print("Building", args.engine, abi, flush=True)
            run(command, target_env, workspace)
            source = workspace / "gopath" / "bin" / f"android_{arch}" / pin["executable"]
            if not source.is_file():
                raise ValueError("Expected cross-compiled executable missing")
            destination = staging / abi / ("lib" + args.engine + ".so")
            destination.parent.mkdir()
            shutil.copyfile(source, destination)
            elf = validate(destination.read_bytes(), abi, 24)
            build_info = run([go, "version", "-m", str(destination)], env, workspace, True)
            expected = "\tmod\t" + pin["module"] + "\t" + pin["version"] + "\t" + pin["sum"]
            verify_build_info(build_info, expected, arch)
            (staging / abi / "BUILD_INFO.txt").write_text(build_info, encoding="utf-8")
            evidence["artifacts"].append({"abi": abi, "sha256": sha(destination),
                                          "bytes": destination.stat().st_size, "elf": elf})
        run([go, "mod", "verify"], env, workspace)
        shutil.copyfile(Path(metadata["Dir"]) / "LICENSE", staging / "LICENSE")
        (staging / "PROVENANCE.json").write_text(json.dumps(evidence, indent=2) + "\n",
                                                 encoding="utf-8")
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(staging, out)
    print("Candidate only:", out)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, choices=ENGINES)
    parser.add_argument("--ndk", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--module-cache", type=Path)
    parser.add_argument("--abi", action="append", choices=ABIS)
    args = parser.parse_args()
    try:
        build(args)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print("Candidate build failed:", error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
