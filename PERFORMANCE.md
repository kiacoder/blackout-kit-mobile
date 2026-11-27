# Performance and reliability status

Published [v1.19.4](https://github.com/kiacoder/blackout-kit-mobile/releases/tag/v1.19.4) (2026-11-27, source 43c6d91; app version 1.19.4+2064). No matched physical-device throughput, battery, PSS or CPU benchmark is established for this release. The dated checkpoints below are historical; see [engineering acceptance](docs/ENGINEERING_ACCEPTANCE.md).

> **2026-11-16 continuation update (supersedes older evidence below):** overall ~26%.
> Latest preservation/security/build review: [review](docs/CONTINUATION_REVIEW.md).
> Official-release-hash-verified Mihomo Linux core: **11 integration tests passed**.
> **30 JVM host tests / 33 Python tests passed (29 factory + 4 artifact checks); eleven-file Android API check passed, including VpnPlugin against official Flutter Java declarations.**
> Android ARM64 candidate verified but API34-targeted, NOT packaged/device-tested.
> Mihomo remains disabled by default; no APK/full Flutter build or server deployment.
> See [detailed evidence and limitations](docs/MIHOMO_CORE_PROGRESS.md).


No CPU/battery/memory/startup improvement is claimed without measurement. New offline
factory bounds input bytes, nesting and profile count, deduplicates before output,
and does no network work. App exports cap encoded output at 8 MiB; they still build
strings in memory and should be profiled for large libraries. New export screen
prepares on selection rather than every widget build. Clipboard payload limits vary
by Android version and platform failures are handled without logging the payload.

Process cleanup now escalates after a 500 ms grace interval, with a second bounded
wait. Two children can cost up to ~2 seconds total; this needs lifecycle/ANR testing.
No new daemon, periodic poller or engine dependency was added to the APK.

Device benchmark plan: at least 30 cold/warm starts per engine, median/p95 tunnel
readiness, peak RSS, idle/active CPU, 30-minute battery runs, throughput/latency under
loss, 100 switch/stop cycles and FD/thread/process counts after teardown. Use identical
servers/profiles/network/thermal conditions. Verify DNS and leak behavior before
optimizing speed; do not call a SOCKS handshake successful VPN forwarding.

Milestone 2: the installed-engine checker discards stdout/stderr directly rather than
capturing an unbounded string or leaving a blocked common-pool reader. Host tests verify
silent and noisy process deadlines. YAML conversion caps input at 1 MiB, depth at 32
and expanded nodes at 20,000. These bounds are not Android performance measurements.
