#!/usr/bin/env python3
"""Read-only, opt-in Android measurement sampler. No traffic or device data export."""
import argparse
import json
import re
import statistics
import subprocess
import time

PACKAGE = "com.blackoutkit.vpn"


def parse_memory(raw):
    match = re.search(r"(?m)^\s*TOTAL PSS:\s*(\d+)", raw)
    if not match:
        match = re.search(r"(?m)^\s*TOTAL\s+(\d+)\s+", raw)
    return int(match[1]) if match else None


def parse_cpu(raw):
    # Sum app processes only; never emit the other process names or raw dump.
    pattern = rf"(?m)^\s*([\d.]+)%\s+\d+/{re.escape(PACKAGE)}(?::[\w.-]+)?:"
    values = [float(item) for item in re.findall(pattern, raw)]
    return sum(values) if values else None


def parse_battery(raw):
    result = {}
    for name in ("level", "temperature", "voltage", "status"):
        match = re.search(rf"(?m)^\s*{name}:\s*(-?\d+)\s*$", raw)
        result[name] = int(match[1]) if match else None
    return result


def read(adb, serial, *command):
    return subprocess.run(
        [adb, "-s", serial, *command], check=True, text=True,
        capture_output=True, timeout=30,
    ).stdout


def sample(adb, serial):
    return {
        "elapsed_monotonic_s": time.monotonic(),
        "pss_kib": parse_memory(read(adb, serial, "shell", "dumpsys", "meminfo", PACKAGE)),
        "cpu_percent": parse_cpu(read(adb, serial, "shell", "dumpsys", "cpuinfo")),
        "battery": parse_battery(read(adb, serial, "shell", "dumpsys", "battery")),
    }


def summarize(samples, field):
    values = [item[field] for item in samples if item[field] is not None]
    return None if not values else {
        "count": len(values), "min": min(values), "max": max(values),
        "median": statistics.median(values),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default="adb")
    parser.add_argument("--serial", required=True, help="Explicitly authorized test device")
    parser.add_argument("--scenario", choices=("idle", "connected", "recovery"), required=True)
    parser.add_argument("--samples", type=int, default=12)
    parser.add_argument("--interval", type=int, default=5)
    args = parser.parse_args()
    if not 1 <= args.samples <= 120 or not 5 <= args.interval <= 60:
        parser.error("Use 1–120 samples and a 5–60 second interval")
    if read(args.adb, args.serial, "get-state").strip() != "device":
        parser.error("Selected device is not authorized")
    readings = []
    start = time.monotonic()
    for index in range(args.samples):
        record = sample(args.adb, args.serial)
        record["elapsed_monotonic_s"] = round(record["elapsed_monotonic_s"] - start, 3)
        readings.append(record)
        if index + 1 < args.samples:
            time.sleep(args.interval)
    print(json.dumps({
        "scenario": args.scenario, "package": PACKAGE,
        "api": read(args.adb, args.serial, "shell", "getprop", "ro.build.version.sdk").strip(),
        "samples": readings, "pss_kib": summarize(readings, "pss_kib"),
        "cpu_percent": summarize(readings, "cpu_percent"),
        "limitations": "Battery level is coarse whole-device data; no power or throughput claim.",
    }, indent=2))


if __name__ == "__main__":
    main()
