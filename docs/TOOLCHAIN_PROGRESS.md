# Milestone 2: build environment and upstream API evidence

> **2026-11-16 continuation update (supersedes older evidence below):** overall ~26%.
> Latest preservation/security/build review: [review](CONTINUATION_REVIEW.md).
> Official-release-hash-verified Mihomo Linux core: **11 integration tests passed**.
> **30 JVM host tests / 33 Python tests passed (29 factory + 4 artifact checks); eleven-file Android API check passed, including VpnPlugin against official Flutter Java declarations.**
> Android ARM64 candidate verified but API34-targeted, NOT packaged/device-tested.
> Mihomo remains disabled by default; no APK/full Flutter build or server deployment.
> See [MIHOMO_CORE_PROGRESS.md](MIHOMO_CORE_PROGRESS.md).


## Recovered tools (development only)
* Java runtime: `jdk4py==17.0.9.2` in ignored `.venv`, via PyPI. This is a JRE,
  not a full JDK (`javac` absent); use a current maintained Java 17 JDK for releases.
* Kotlin compiler: `kotlin-compiler@1.9.25`, npm package, scripts disabled.
  Tarball SHA-256: bb497321b994d459bf611d970f85936b1f6998089dc8686b7530fcc1728b9319.
* Go: `go-bin==1.26.6`, PyPI binary distribution, development testing only.
* Android API 34 compile jar: Sable/android-platforms mirror blob
  923bafccf73aef996495c559e919ad8be3cabd58; SHA-256
  6cea1df3efb77103ac3e2beb9bf4718964b0e0869ab16d39d29d5cbae1c147ad.
  This is NOT an installed SDK/NDK, build-tools or verified Google SDK distribution.
  Used only for a narrow compile check. Prefer the SDK's android.jar on a provisioned host.

No cached Flutter/Dart, SDK/NDK, full JDK, Gradle dependencies, /dev/kvm or USB device
were found. Official Kotlin release download redirected to release-assets.githubusercontent.com
and failed TLS connection. No attempt was made to bypass the host allowlist. npm
provided a permitted compiler distribution. Several candidate JUnit mirror files were
LFS pointers/invalid or failed the expected hash; none was executed. A standalone
host test harness avoids that dependency. The official JUnit repository's Hamcrest
jar was readable, but that alone is insufficient to run JUnit.

Mihomo v1.19.34 source was retrieved and checked (module identity, exact commit and
GPL license). A real `go build` attempt failed retrieving modules from proxy.golang.org
(EOF), before engine compilation. GitHub-only source acquisition is insufficient for
its non-GitHub module paths, checksum service and Android cgo/NDK requirements. We did
not disable checksum verification, import arbitrary replacement binaries, or claim a
successful build. Root default-branch metadata was not reliable evidence of the VPN
engine; the pinned release tag is mandatory in the new build script.

## Reproduce the completed narrow checks
```
export JAVA_HOME="$PWD/.venv/lib/python3.11/site-packages/jdk4py/java-runtime"
export KOTLINC="$PWD/.cache/toolchains/package/bin/kotlinc"
bash tool/test_engine_host.sh
ANDROID_API_JAR="$PWD/.cache/toolchains/android-34.jar" bash tool/check_android_engine_sources.sh
.venv/bin/python -m unittest discover -s tool/tests -v
```
No whole-application compilation or Android UI testing is implied. The tool/cache
paths are ephemeral; scripts also accept ordinary JAVA_HOME/KOTLINC/ANDROID_API_JAR.

## Official backend investigation — not yet integration
* AmneziaWG Android ff15093bf3856fea0947923474870b86efb682f0: official Java backend
  owns its VpnService; awgTurnOn consumes a detached TUN fd and UAPI settings, then
  awgGetSocketV4/V6 descriptors are protected. Stop must retain the matching backend
  instance/handle. The JNI class is org.amnezia.awg.GoBackend. Its current module
  requires Go 1.25 and AWG-Go v3.1.20260814, while the checked Makefile pins a patched
  Go 1.24.2: resolve that build mismatch before choosing a release. This is not proof
  of AWG protocol version interoperability. No AWG JNI library was built/added.
* Official WireGuard Android e7b3a3c118836e112620b1302a8ba1873ad4daac: similar
  backend-owned service, wgTurnOn with detached descriptor and protected v4/v6
  sockets. A second backend service cannot safely coexist with the existing VPN
  owner. No standard WG-as-AWG substitution implemented.
* OpenVPN3 0c1ce172fe918b05463d71e682a0c2f2d8fe7899: client/ovpncli.hpp exposes
  eval_config, blocking connect, stop/reconnect and socket_protect callbacks;
  Android integration needs its TUN-builder interface, credentials and JNI glue.
  No C++/NDK/dependency build possible here. Existing reference JNI is GPL application
  code, not a drop-in MIT wrapper. No OpenVPN adapter is claimed implemented.
* Xray's bundled Libv2ray class does not expose a standalone checkConfig API.
  libbox exposes checkConfig but is a separate native API/version; it cannot certify
  arbitrary Xray configs. Existing successful selection paths were preserved.

## Secure server access investigation
No SSH directory or agent socket is available. The three IPs are outside the allowed
outbound hosts. No connection attempted, no credentials searched in reference profiles,
no server settings inferred. A secure authorized network/account/agent/fingerprint
channel remains required. The public GitHub repo was not used to publish private
changes for remote CI. An authorized private runner/workspace would unblock builds.
