#!/usr/bin/env bash
# 交叉编译 core-mobile 为 Android .so（arm64-v8a / armeabi-v7a / x86_64），输出到 apps/android/core-engine/src/main/jniLibs。
# 需要 ANDROID_NDK_HOME 与 cargo-ndk（cargo install cargo-ndk）。CI 与本地均用此脚本。
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/apps/android/core-engine/src/main/jniLibs}
ABIS=${ABIS:-"arm64-v8a armeabi-v7a x86_64"}
cd "$ROOT/core-mobile"
for abi in $ABIS; do
  case $abi in arm64-v8a) t=aarch64-linux-android;; armeabi-v7a) t=armv7-linux-androideabi;; x86_64) t=x86_64-linux-android;; x86) t=i686-linux-android;; esac
  rustup target add $t >/dev/null
done
ARGS=(); for abi in $ABIS; do ARGS+=(-t "$abi"); done
cargo ndk "${ARGS[@]}" --platform 26 -o "$OUT" build --release --lib
find "$OUT" -name '*.so' -exec ls -la {} \;
