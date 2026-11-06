#!/usr/bin/env bash
# 构建嵌入式 mihomo（mihomo-mobile/）。
#   tools/build-mihomo.sh android   → apps/android/core-engine/src/main/jniLibs/<abi>/libzmihomo.so（需 ANDROID_NDK_HOME）
#   tools/build-mihomo.sh ios       → build/ios/Zmihomo.xcframework（macOS，c-archive，真机 + 模拟器）
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/mihomo-mobile"
TAGS="with_gvisor"
LDFLAGS="-s -w -buildid="
export CGO_ENABLED=1
case "${1:-}" in
android)
  NDK=${ANDROID_NDK_HOME:?需要 ANDROID_NDK_HOME}
  TC=$(echo "$NDK"/toolchains/llvm/prebuilt/*/bin)
  OUT=${OUT:-$ROOT/apps/android/core-engine/src/main/jniLibs}
  for abi in ${ABIS:-arm64-v8a x86_64}; do
    case $abi in
      arm64-v8a) GA=arm64; CCB=aarch64-linux-android26-clang;;
      armeabi-v7a) GA=arm; CCB=armv7a-linux-androideabi26-clang; export GOARM=7;;
      x86_64) GA=amd64; CCB=x86_64-linux-android26-clang;;
    esac
    mkdir -p "$OUT/$abi"
    GOOS=android GOARCH=$GA CC="$TC/$CCB" go build -trimpath -tags "$TAGS" -ldflags "$LDFLAGS" -buildmode=c-shared -o "$OUT/$abi/libzmihomo.so" .
    rm -f "$OUT/$abi/libzmihomo.h"
  done
  find "$OUT" -name 'libzmihomo.so' -exec ls -la {} \;
  ;;
ios)
  OUT=$ROOT/build/ios/zmihomo; rm -rf "$OUT"; mkdir -p "$OUT"
  build() { # sdk goarch clangarch outdir
    SDK=$(xcrun --sdk $1 --show-sdk-path); CCX=$(xcrun --sdk $1 -f clang)
    local tgt=$3-apple-ios17.0; [[ $1 == iphonesimulator ]] && tgt=$tgt-simulator
    mkdir -p "$4"
    GOOS=ios GOARCH=$2 CC="$CCX" CGO_CFLAGS="-isysroot $SDK -target $tgt" CGO_LDFLAGS="-isysroot $SDK -target $tgt" \
      go build -trimpath -tags "$TAGS" -ldflags "$LDFLAGS" -buildmode=c-archive -o "$4/libzmihomo.a" .
  }
  build iphoneos arm64 arm64 "$OUT/ios"
  build iphonesimulator arm64 arm64 "$OUT/sim-arm64"
  build iphonesimulator amd64 x86_64 "$OUT/sim-x64"
  mkdir -p "$OUT/sim" "$OUT/headers"
  lipo -create "$OUT/sim-arm64/libzmihomo.a" "$OUT/sim-x64/libzmihomo.a" -output "$OUT/sim/libzmihomo.a"
  cp "$OUT/ios/libzmihomo.h" "$OUT/headers/zmihomo.h"
  printf 'module Zmihomo {\n  header "zmihomo.h"\n  export *\n}\n' > "$OUT/headers/module.modulemap"
  xcodebuild -create-xcframework -library "$OUT/ios/libzmihomo.a" -headers "$OUT/headers" -library "$OUT/sim/libzmihomo.a" -headers "$OUT/headers" -output "$ROOT/build/ios/Zmihomo.xcframework"
  ;;
*) echo "用法：$0 android|ios"; exit 2;;
esac
