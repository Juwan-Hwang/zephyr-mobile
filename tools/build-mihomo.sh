#!/usr/bin/env bash
# 构建嵌入式 mihomo（mihomo-mobile/）。
#   tools/build-mihomo.sh android   → apps/android/core-engine/src/main/jniLibs/<abi>/libzmihomo.so（需 ANDROID_NDK_HOME）
#   tools/build-mihomo.sh ohos      → build/ohos/arm64-v8a/libzmihomo.so（需 GO_OHOS_ROOT=go-patch 1.27.3、OHOS_NDK_HOME=<OpenHarmony SDK>/native；c-shared，供 apps/harmony 拷入 libs/arm64-v8a）
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
    # 16 KB 页对齐（Android 15+ / Play 要求 PT_LOAD p_align ≥ 16384），由外部链接器（NDK clang/lld）生效。
    GOOS=android GOARCH=$GA CC="$TC/$CCB" go build -trimpath -tags "$TAGS" -ldflags "$LDFLAGS -extldflags=-Wl,-z,max-page-size=16384" -buildmode=c-shared -o "$OUT/$abi/libzmihomo.so" .
    rm -f "$OUT/$abi/libzmihomo.h"
  done
  find "$OUT" -name 'libzmihomo.so' -exec ls -la {} \;
  # 打印每个 .so 的 LOAD 段对齐，便于在 CI 日志里核对（期望 0x4000）。
  if command -v "$TC/llvm-readelf" >/dev/null; then
    for so in "$OUT"/*/libzmihomo.so; do echo "$so"; "$TC/llvm-readelf" -lW "$so" | grep -E '^\s*LOAD' || true; done
  fi
  ;;
ohos)
  # 鸿蒙（arm64）：c-shared，VpnExtensionAbility 里 dlopen。
  # OHOS 的 musl 对 dlopen 库里的 initial-exec TLS 硬拒绝（"initial-exec TLS resolves to dynamic definition"），
  # 上游 Go 的 linux/arm64 c-shared 必带 R_AARCH64_TLS_TPREL64（runtime.tlsg），GOOS=android 又在 ArkTS 线程上崩，
  # 所以用打过补丁的 go-patch 1.27.3（GOOS=openharmony，arm64 shared 走 TLSDESC），C 侧 TLS 用 global-dynamic。
  #   GO_OHOS_ROOT   go-patch 的 GOROOT（含 ohos-scripts/cc-arm64），tarball SHA256 e116579274f1cf446b4916f85d978e236dc500246f8062fffd5f9ed9ae4bb05d
  #   OHOS_NDK_HOME  OpenHarmony SDK 的 native 目录（llvm/bin + sysroot），6.1-Release / API 23 起
  # gVisor：OHOS SELinux 不许 fstat 系统交来的 TUN fd，fdbased.IsSocketFD 会失败。在临时构建目录里拷一份
  # metacubex/gvisor 打 mihomo-mobile/patches/gvisor-fstat-tun.patch（EACCES/EPERM 视为非 socket），再 -replace；
  # 仓库里的 mihomo-mobile/go.mod 不变，iOS / Android 不受影响。
  GOR=${GO_OHOS_ROOT:?需要 GO_OHOS_ROOT（go-patch 1.27.3 的 GOROOT）}
  NDK=${OHOS_NDK_HOME:?需要 OHOS_NDK_HOME（OpenHarmony SDK 的 native 目录）}
  GO=$GOR/bin/go; [[ -x $GO ]] || { echo "缺 $GO" >&2; exit 1; }
  RE=$NDK/llvm/bin/llvm-readelf; NM=$NDK/llvm/bin/llvm-nm
  OUT=${OUT:-$ROOT/build/ohos}; SO=$OUT/arm64-v8a/libzmihomo.so
  BUILD=${BUILD_DIR:-$ROOT/build/ohos-work}
  mkdir -p "$OUT/arm64-v8a" "$BUILD"
  export GOROOT=$GOR GOTOOLCHAIN=local GOFLAGS=-mod=mod GOOS=openharmony GOARCH=arm64
  export CC="$GOR/ohos-scripts/cc-arm64" CXX="$GOR/ohos-scripts/cxx-arm64" AR="$NDK/llvm/bin/llvm-ar"
  export CGO_CFLAGS="-O2 -g0 -ftls-model=global-dynamic"
  SRC=$BUILD/src; rm -rf "$SRC"; mkdir -p "$SRC"
  cp go.mod go.sum "$SRC/"
  find . -maxdepth 1 -name '*.go' ! -name '*_test.go' -exec cp {} "$SRC/" \;
  cd "$SRC"
  "$GO" mod download github.com/metacubex/gvisor
  GV_VER=$("$GO" list -m -f '{{.Version}}' github.com/metacubex/gvisor)
  GV_DIR=$("$GO" list -m -f '{{.Dir}}' github.com/metacubex/gvisor)
  PATCH=$ROOT/mihomo-mobile/patches/gvisor-fstat-tun.patch
  PG=$BUILD/gvisor-$GV_VER
  if ! cmp -s "$PATCH" "$PG/.zephyr-patch"; then
    rm -rf "$PG"; cp -R "$GV_DIR" "$PG"; chmod -R u+w "$PG"
    (cd "$PG" && git apply -p1 "$PATCH")
    cp "$PATCH" "$PG/.zephyr-patch"
  fi
  "$GO" mod edit -replace="github.com/metacubex/gvisor=$PG"
  MV=$("$GO" list -m -f '{{.Version}}' github.com/metacubex/mihomo)
  echo "go $("$GO" env GOVERSION)，mihomo $MV，gvisor $GV_VER（已打 fstat 补丁）"
  "$GO" build -trimpath -tags "$TAGS" \
    -ldflags "$LDFLAGS -X github.com/metacubex/mihomo/constant.Version=$MV -extldflags=-Wl,-soname,libzmihomo.so" \
    -buildmode=c-shared -o "$SO" .
  rm -f "$OUT/arm64-v8a/libzmihomo.h"
  # 构建后检查：先读进变量再 grep（避免 grep -q 提前退出 + pipefail 误判）。
  fail=0; ls -la "$SO"
  RELOCS=$("$RE" -rW "$SO"); DYN=$("$RE" -dW "$SO")
  grep -oE 'R_AARCH64_[A-Z0-9_]*TLS[A-Z0-9_]*' <<<"$RELOCS" | sort | uniq -c || true
  if grep -Eq 'R_AARCH64_(TLS_TPREL|TLSLE_|TLSIE_)' <<<"$RELOCS"; then echo "错误：含 initial-exec/local-exec TLS 重定位，OHOS dlopen 会拒绝" >&2; fail=1; fi
  if grep -q STATIC_TLS <<<"$DYN"; then echo "错误：DF_STATIC_TLS 置位" >&2; fail=1; fi
  for n in $(sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' <<<"$DYN"); do
    [[ -e $NDK/sysroot/usr/lib/aarch64-linux-ohos/$n ]] || { echo "错误：DT_NEEDED $n 不在 OHOS sysroot" >&2; fail=1; }
  done
  DEFS=$("$NM" -D --defined-only "$SO" | awk '{print $NF}')
  for s in $(grep -h '^//export ' "$ROOT"/mihomo-mobile/*.go | awk '{print $2}'); do
    grep -qx "$s" <<<"$DEFS" || { echo "错误：缺少导出 $s" >&2; fail=1; }
  done
  [[ $fail == 0 ]] || exit 1
  echo "OK：无静态 TLS，DT_NEEDED 都在 sysroot，导出齐全"
  ;;
ios)
  OUT=$ROOT/build/ios/zmihomo; rm -rf "$OUT"; mkdir -p "$OUT"
  build() { # sdk goarch clangarch outdir
    SDK=$(xcrun --sdk "$1" --show-sdk-path); CCX=$(xcrun --sdk "$1" -f clang)
    local tgt=$3-apple-ios17.0; [[ $1 == iphonesimulator ]] && tgt=$tgt-simulator
    mkdir -p "$4"
    GOOS=ios GOARCH=$2 CC="$CCX" CGO_CFLAGS="-isysroot $SDK -target $tgt" CGO_LDFLAGS="-isysroot $SDK -target $tgt" \
      go build -trimpath -tags "$TAGS" -ldflags "$LDFLAGS" -buildmode=c-archive -o "$4/libzmihomo.a" .
  }
  build iphoneos arm64 arm64 "$OUT/ios"
  build iphonesimulator arm64 arm64 "$OUT/sim-arm64"
  build iphonesimulator amd64 x86_64 "$OUT/sim-x64"
  # 头文件放子目录，避免与 ZephyrMobileCore.xcframework 的 module.modulemap 在 Products/include 撞车。
  mkdir -p "$OUT/sim" "$OUT/headers/Zmihomo"
  lipo -create "$OUT/sim-arm64/libzmihomo.a" "$OUT/sim-x64/libzmihomo.a" -output "$OUT/sim/libzmihomo.a"
  cp "$OUT/ios/libzmihomo.h" "$OUT/headers/Zmihomo/zmihomo.h"
  printf 'module Zmihomo {\n  header "zmihomo.h"\n  export *\n}\n' > "$OUT/headers/Zmihomo/module.modulemap"
  xcodebuild -create-xcframework -library "$OUT/ios/libzmihomo.a" -headers "$OUT/headers" -library "$OUT/sim/libzmihomo.a" -headers "$OUT/headers" -output "$ROOT/build/ios/Zmihomo.xcframework"
  ;;
*) echo "用法：$0 android|ios|ohos"; exit 2;;
esac
