#!/usr/bin/env bash
# 在 macOS 上构建 ZephyrMobileCore.xcframework（真机 arm64 + 模拟器 arm64/x86_64），含 Swift 绑定所需头文件与 modulemap。
# 输出：build/ios/ZephyrMobileCore.xcframework 与 build/ios/Sources/*.swift
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/build/ios
cd "$ROOT/core-mobile"
TARGETS="aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios"
for t in $TARGETS; do rustup target add $t >/dev/null; IPHONEOS_DEPLOYMENT_TARGET=17.0 cargo build --release --lib --target $t; done
T=${CARGO_TARGET_DIR:-$ROOT/core-mobile/target}
rm -rf "$OUT" && mkdir -p "$OUT/headers" "$OUT/sim" "$OUT/Sources"
cp bindings/swift/*.h "$OUT/headers/"
cat bindings/swift/*.modulemap > "$OUT/headers/module.modulemap"
cp bindings/swift/*.swift "$OUT/Sources/"
lipo -create "$T/aarch64-apple-ios-sim/release/libzephyr_mobile_core.a" "$T/x86_64-apple-ios/release/libzephyr_mobile_core.a" -output "$OUT/sim/libzephyr_mobile_core.a"
xcodebuild -create-xcframework \
  -library "$T/aarch64-apple-ios/release/libzephyr_mobile_core.a" -headers "$OUT/headers" \
  -library "$OUT/sim/libzephyr_mobile_core.a" -headers "$OUT/headers" \
  -output "$OUT/ZephyrMobileCore.xcframework"
echo "→ $OUT/ZephyrMobileCore.xcframework"
