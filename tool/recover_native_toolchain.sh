#!/usr/bin/env bash
# Development-only recovery through permitted hosts. NOT a complete Android SDK.
# No public writes, no signing material, no runtime APK installation.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .cache/toolchains .cache/references
recover() {
  local repo="$1" ref="$2" pin="$3" dest="$4"; shift 4
  if [[ ! -e "$dest" ]]; then
    git clone --depth 1 --branch "$ref" --filter=blob:none --sparse "https://github.com/$repo.git" "$dest"
  fi
  [[ "$(git -C "$dest" rev-parse HEAD)" == "$pin" ]] || {
    echo 'Unexpected cached source revision; refusing to replace it.' >&2; exit 1;
  }
  git -C "$dest" sparse-checkout add "$@"
}
recover denoland/android_ndk main 401019bf85744311b26c88ced255cd53401af8b7 \
  .cache/toolchains/android-ndk-r22 toolchains/llvm/prebuilt/linux-x86_64 sources build
recover msft-mirror-aosp/platform.prebuilts.jdk.jdk17 android13-d1-release \
  c253484c29dfee6f91cc1f616b5cce87a299d511 .cache/toolchains/aosp-jdk17 linux-x86
# These are OLD development mirrors, not current production toolchain approval.
.cache/toolchains/aosp-jdk17/linux-x86/bin/javac -version
.cache/toolchains/android-ndk-r22/toolchains/llvm/prebuilt/linux-x86_64/bin/clang --version
if [[ ! -d .venv ]]; then python3 -m venv .venv; fi
.venv/bin/pip install -r tool/requirements-config.txt go-bin==1.26.6 cmake==3.22.6 ninja==1.13.2
if [[ ! -e .cache/toolchains/kotlin-compiler-1.9.25.tgz ]]; then
  npm pack kotlin-compiler@1.9.25 --ignore-scripts --pack-destination .cache/toolchains
fi
echo 'bb497321b994d459bf611d970f85936b1f6998089dc8686b7530fcc1728b9319  .cache/toolchains/kotlin-compiler-1.9.25.tgz' | sha256sum -c -
if [[ ! -d .cache/toolchains/package ]]; then
  tar -xzf .cache/toolchains/kotlin-compiler-1.9.25.tgz -C .cache/toolchains
fi
chmod +x .cache/toolchains/package/bin/kotlinc
echo 'Recovered development JDK/NDK/Go/CMake/Ninja/Kotlin; Flutter, complete SDK and Gradle dependencies still required.'
