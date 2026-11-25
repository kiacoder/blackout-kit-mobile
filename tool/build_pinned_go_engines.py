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


def dependency_records(info):
    """Retain module version, checksum and any replacement as a single record."""
    records = {}
    previous = None
    for line in info.splitlines():
        fields = line.split("\t")
        if len(fields) >= 2 and fields[0] == "" and fields[1] == "dep":
            if len(fields) not in (4, 5) or not fields[2] or fields[2] in records:
                raise ValueError("Invalid or duplicate dependency metadata")
            previous = fields[2]
            records[previous] = fields[3:]
        elif len(fields) >= 2 and fields[0] == "" and fields[1] == "=>":
            if previous is None or len(fields) not in (3, 4, 5):
                raise ValueError("Unexpected module replacement")
            records[previous] += fields[1:]
            previous = None
        else:
            previous = None
    if not records:
        raise ValueError("No dependency metadata")
    return records


def dependency_diff(baseline, candidate):
    old, new = dependency_records(baseline), dependency_records(candidate)
    return [{"module": name, "baseline": old.get(name), "candidate": new.get(name)}
            for name in sorted(old.keys() | new.keys()) if old.get(name) != new.get(name)]


def decode_module_downloads(raw):
    decoder = json.JSONDecoder()
    records = {}
    while raw.strip():
        raw = raw.lstrip()
        record, end = decoder.raw_decode(raw)
        raw = raw[end:]
        name = record["Path"]
        if name in records or record.get("Error"):
            raise ValueError("Duplicate or failed module download")
        records[name] = record
    return records


def validate_lock(lock, engine, pin):
    if lock.get("schema") != 1 or lock.get("engine") != engine:
        raise ValueError("Unexpected engine lock schema or identity")
    records = {}
    for record in lock["modules"]:
        name, version = record["path"], record["version"]
        if (not name or any(c.isspace() for c in name + version)
                or name.startswith("-") or "@" in name
                or not version.startswith("v") or name in records
                or not all(record[key].startswith("h1:") for key in ("sum", "mod_sum"))):
            raise ValueError("Invalid locked module")
        records[name] = record
    main = records.get(pin["module"])
    if not main or (main["version"], main["sum"], main["mod_sum"]) != (
            pin["version"], pin["sum"], pin["mod_sum"]):
        raise ValueError("Locked main module does not match source pin")
    return records


def prepare_locked_workspace(engine, pin, go, env, workspace):
    lock_path = ROOT / "tool/go_engine_locks" / (engine + ".json")
    lock = json.loads(lock_path.read_text(encoding="utf-8"))
    records = validate_lock(lock, engine, pin)
    linked = {name: [record["version"], record["sum"]]
              for name, record in records.items() if name != pin["module"]}
    for abi in ABIS:
        baseline = ROOT / "android/app/src/main/jniLibs" / abi / ("lib" + engine + ".so")
        info = run([go, "version", "-m", str(baseline)], env, workspace, True)
        if sha(baseline) != lock["baseline_sha256"][abi] or dependency_records(info) != linked:
            raise ValueError("Bundled binary does not match the reviewed lock snapshot")
    # Download only modules linked into the baseline binaries, not the
    # unrelated test and optional dependency archives in the full graph.
    specs = [name + "@" + record["version"] for name, record in sorted(records.items())]
    downloads = decode_module_downloads(run([go, "mod", "download", "-json", *specs],
                                            env, workspace, True))
    if downloads.keys() != records.keys():
        raise ValueError("Unexpected downloaded module set")
    for name, record in records.items():
        actual = downloads[name]
        if (actual["Version"], actual["Sum"], actual["GoModSum"]) != (
                record["version"], record["sum"], record["mod_sum"]):
            raise ValueError("Locked dependency checksum mismatch: " + name)
    verify_source(downloads[pin["module"]], pin)
    requirements = "".join(f"\t{name} {record['version']}\n"
                           for name, record in sorted(records.items()))
    sums = "".join(f"{name} {record['version']} {record['sum']}\n"
                   f"{name} {record['version']}/go.mod {record['mod_sum']}\n"
                   for name, record in sorted(records.items()))
    (workspace / "go.mod").write_text(
        "module blackout-rebuild-audit\n\ngo 1.27.0\n\nrequire (\n" + requirements + ")\n",
        encoding="utf-8", newline="\n")
    (workspace / "go.sum").write_text(sums, encoding="utf-8", newline="\n")
    return sha(lock_path)


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
        lock_digest = None
        if args.locked:
            lock_digest = prepare_locked_workspace(args.engine, pin, go, env, workspace)
        else:
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
            "lock_sha256": lock_digest,
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
            destination = staging / abi / ("lib" + args.engine + ".so")
            destination.parent.mkdir()
            common = ["-trimpath", "-buildvcs=false", "-buildmode=pie", "-ldflags=-s -w"]
            if pin["tags"]:
                common.append("-tags=" + pin["tags"])
            print("Building", args.engine, abi, flush=True)
            if args.locked:
                run([go, "build", "-mod=readonly", *common, "-o", str(destination),
                     pin["package"]], target_env, workspace)
            else:
                run([go, "install", *common, pin["package"] + "@" + pin["version"]],
                    target_env, workspace)
                source = workspace / "gopath" / "bin" / f"android_{arch}" / pin["executable"]
                if not source.is_file():
                    raise ValueError("Expected cross-compiled executable missing")
                shutil.copyfile(source, destination)
            elf = validate(destination.read_bytes(), abi, 24)
            build_info = run([go, "version", "-m", str(destination)], env, workspace, True)
            expected = "\tmod\t" + pin["module"] + "\t" + pin["version"] + "\t" + pin["sum"]
            verify_build_info(build_info, expected, arch)
            (staging / abi / "BUILD_INFO.txt").write_text(build_info, encoding="utf-8")
            baseline = ROOT / "android/app/src/main/jniLibs" / abi / destination.name
            baseline_info = run([go, "version", "-m", str(baseline)], env, workspace, True)
            differences = dependency_diff(baseline_info, build_info)
            if differences and (args.locked or args.require_matching_dependencies):
                raise ValueError("Dependency graph differs from bundled binary")
            evidence["artifacts"].append({
                "abi": abi, "sha256": sha(destination),
                "bytes": destination.stat().st_size, "elf": elf,
                "baseline_sha256": sha(baseline),
                "dependency_differences": differences,
                "dependency_match": not differences,
            })
        run([go, "mod", "verify"], env, workspace)
        if args.locked:
            for name in ("go.mod", "go.sum"):
                shutil.copyfile(workspace / name, staging / name)
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
    parser.add_argument("--locked", action="store_true",
                        help="Use the verified bundled linked-module snapshot; enforce exact match")
    parser.add_argument("--require-matching-dependencies", action="store_true",
                        help="Reject any dependency difference from the bundled binary")
    args = parser.parse_args()
    try:
        build(args)
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print("Candidate build failed:", error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
