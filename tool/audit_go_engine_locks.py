#!/usr/bin/env python3
"""Query OSV for linked Go module versions; findings do not establish reachability."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys
import urllib.request
import urllib.error
import time

ROOT = Path(__file__).resolve().parents[1]
URL = "https://api.osv.dev/v1/querybatch"
ENGINES = ("singbox", "tun2socks")


def load_queries(root):
    owners = {}
    hashes = {}
    for engine in ENGINES:
        raw = (root / "tool/go_engine_locks" / (engine + ".json")).read_bytes()
        lock = json.loads(raw)
        if lock.get("schema") != 1 or lock.get("engine") != engine:
            raise ValueError("Invalid lock identity")
        hashes[engine] = hashlib.sha256(raw).hexdigest()
        seen = set()
        for module in lock["modules"]:
            key = (module["path"], module["version"])
            if key[0] in seen or not all(key):
                raise ValueError("Invalid or duplicate locked module")
            seen.add(key[0])
            owners.setdefault(key, []).append(engine)
    return owners, hashes


def request_batch(queries):
    request = urllib.request.Request(
        URL, data=json.dumps({"queries": queries}).encode("utf-8"),
        headers={"Content-Type": "application/json"}, method="POST",
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code not in (429, 500, 502, 503, 504) or attempt == 3:
                raise
            error.close()
        except (urllib.error.URLError, TimeoutError):
            if attempt == 3:
                raise
        time.sleep(2 ** (attempt + 1))
    raise RuntimeError("Unreachable retry state")


def audit(root, fetch=request_batch):
    owners, hashes = load_queries(root)
    findings = []
    keys = sorted(owners)
    for start in range(0, len(keys), 50):
        batch = keys[start:start + 50]
        queries = [{"package": {"ecosystem": "Go", "name": name}, "version": version}
                   for name, version in batch]
        response = fetch(queries)
        results = response.get("results")
        if not isinstance(results, list) or len(results) != len(batch):
            raise ValueError("Incomplete OSV response")
        for (name, version), result in zip(batch, results, strict=True):
            if not isinstance(result, dict) or result.keys() - {"vulns"}:
                raise ValueError("Unsupported or incomplete OSV result")
            vulnerabilities = result.get("vulns", [])
            if not isinstance(vulnerabilities, list):
                raise ValueError("Invalid vulnerability list")
            seen = set()
            for advisory in vulnerabilities:
                identifier = advisory["id"]
                if not isinstance(identifier, str) or not identifier or identifier in seen:
                    raise ValueError("Invalid advisory identity")
                seen.add(identifier)
                findings.append({"module": name, "version": version,
                                 "engines": owners[(name, version)], "id": identifier,
                                 "modified": advisory.get("modified")})
    return {"schema": 1, "source": URL,
            "checked_at": datetime.now(timezone.utc).isoformat(),
            "scope": "linked-module-version-only; no reachability or standard-library assessment",
            "lock_sha256": hashes, "unique_module_versions": len(keys),
            "findings": findings}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--fail-on-findings", action="store_true")
    args = parser.parse_args()
    try:
        report = audit(ROOT)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"Audit incomplete: {error}", file=sys.stderr)
        return 2
    print(f"Queried {report['unique_module_versions']} module versions; "
          f"{len(report['findings'])} module/advisory matches.")
    for finding in report["findings"]:
        print(f"{finding['module']} {finding['version']}: {finding['id']}")
    return 1 if args.fail_on_findings and report["findings"] else 0


if __name__ == "__main__":
    sys.exit(main())
