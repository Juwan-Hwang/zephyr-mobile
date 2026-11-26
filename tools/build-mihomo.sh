#!/usr/bin/env bash
# 构建嵌入式 mihomo（mihomo-mobile/）。
#   tools/build-mihomo.sh android   → apps/android/core-engine/src/main/jniLibs/<abi>/libzmihomo.so（需 ANDROID_NDK_HOME）
#   tools/build-mihomo.sh ohos      → build/ohos/arm64-v8a/libzmihomo.so（需 GO_OHOS_ROOT=go-patch 1.27.3、OHOS_NDK_HOME=<OpenHarmony SDK>/native；c-shared，供 apps/harmony 拷入 libs/arm64-v8a）
#   tools/build-mihomo.sh ios       → build/ios/Zmihomo.xcframework（macOS，c-archive，真机 + 模拟器）
#   tools/build-mihomo.sh check-patches → 每个目标的补丁都能打上、改到的包 go vet 通过（android 另做 GOOS=android 类型检查）、补丁自带测试在 linux 上跑（CI core 作业）
#   tools/build-mihomo.sh verify-android-so [dir] → 确认 jniLibs 下每个 libzmihomo.so 含 Android 包规则补丁的字符串
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CALLER_PWD=$PWD
cd "$ROOT/mihomo-mobile"
TAGS="with_gvisor"
LDFLAGS="-s -w -buildid="
export CGO_ENABLED=1

# 把补丁 $2 打到依赖拷贝 $1 上，并确认真的打上了。
# 构建目录默认在仓库工作区里（build/…）：在外层 git 仓库的子目录里跑 `git apply`，路径按外层仓库根解析，
# cwd 之外的文件会被静默跳过（"Skipped patch"）且退出码为 0——#330 的 Android 补丁就是这样没进 .so（#1）。
# GIT_CEILING_DIRECTORIES=<拷贝的上级目录> 让 git 不再往上找仓库，git apply 按普通目录打补丁。
# 打完再用反向 --check 验证（反向能干净撤销 = 补丁内容都在），并逐个确认 +++ b/ 的文件存在，否则退出 1。
apply_patch() {
  local dir=$1 patch=$2 f
  ( cd "$dir" && GIT_CEILING_DIRECTORIES=$(dirname "$dir") git apply -p1 "$patch" ) \
    || { echo "错误：$(basename "$patch") 打不上 $dir" >&2; exit 1; }
  ( cd "$dir" && GIT_CEILING_DIRECTORIES=$(dirname "$dir") git apply -p1 --check -R "$patch" ) \
    || { echo "错误：$(basename "$patch") 打完后反向检查失败（补丁没有真正进 ${dir}）" >&2; exit 1; }
  while read -r f; do
    [[ -f $dir/$f ]] || { echo "错误：$(basename "$patch") 应改到的 $f 不在 $dir" >&2; exit 1; }
  done < <(sed -n 's#^+++ b/##p' "$patch")
}

# 在临时构建目录里拷一份 mihomo-mobile 源码，把 mihomo-mobile/patches/series 里「用于」含 $2 的补丁
# 打到对应依赖的拷贝上，再 go mod edit -replace；之后在该目录里构建。仓库里的 go.mod / go.sum 不变。
# 用法：patched_src <构建目录> <目标>（调用后当前目录 = 临时源码目录）
patched_src() {
  local build=$1 target=$2 patch mod targets ver dir pg
  local src=$build/src
  rm -rf "$src"; mkdir -p "$src"
  cp go.mod go.sum "$src/"
  find . -maxdepth 1 -name '*.go' ! -name '*_test.go' -exec cp {} "$src/" \;
  cd "$src"
  while read -r patch mod targets; do
    [[ -z ${patch} || ${patch} == \#* ]] && continue
    [[ ,${targets}, == *,${target},* ]] || continue
    patch=$ROOT/mihomo-mobile/patches/${patch}
    go mod download "$mod"
    ver=$(go list -m -f '{{.Version}}' "$mod"); dir=$(go list -m -f '{{.Dir}}' "$mod")
    pg=$build/${mod##*/}-${ver}
    # 每次都从模块缓存重新拷一份再打（不靠 .zephyr-patch 标记跳过：旧的标记可能来自没真正打上的那次）。
    rm -rf "$pg"; cp -R "$dir" "$pg"; chmod -R u+w "$pg"
    apply_patch "$pg" "$patch"
    go mod edit -replace="$mod=$pg"
    echo "${mod} ${ver}：已打 $(basename "$patch")"
  done < "$ROOT/mihomo-mobile/patches/series"
}
case "${1:-}" in
android)
  NDK=${ANDROID_NDK_HOME:?需要 ANDROID_NDK_HOME}
  TC=$(echo "$NDK"/toolchains/llvm/prebuilt/*/bin)
  OUT=${OUT:-$ROOT/apps/android/core-engine/src/main/jniLibs}
  # 非 root 应用读不了 /data/system/packages.xml（Android 16 实测 permission denied），上游 sing_tun 每次起 TUN
  # 都去读，导致 TUN 起不来；android-package-rules.patch 改成只在配了 include-package/exclude-package 时才读（#1）。
  export GOFLAGS=-mod=mod
  patched_src "${BUILD_DIR:-$ROOT/build/android-work}" android
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
  "$ROOT/tools/build-mihomo.sh" verify-android-so "$OUT"
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
  # 仓库里的 mihomo-mobile/go.mod 不变，iOS 不受影响；Android 只打 android-package-rules.patch（清单见 mihomo-mobile/patches/series）。
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
  rm -rf "$PG"; cp -R "$GV_DIR" "$PG"; chmod -R u+w "$PG"
  apply_patch "$PG" "$PATCH"
  "$GO" mod edit -replace="github.com/metacubex/gvisor=$PG"
  MV=$("$GO" list -m -f '{{.Version}}' github.com/metacubex/mihomo)
  echo "go $("$GO" env GOVERSION)，mihomo ${MV}，gvisor ${GV_VER}（已打 fstat 补丁）"
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
  while read -r n; do
    [[ -z $n || -e $NDK/sysroot/usr/lib/aarch64-linux-ohos/$n ]] || { echo "错误：DT_NEEDED $n 不在 OHOS sysroot" >&2; fail=1; }
  done < <(sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' <<<"$DYN")
  DEFS=$("$NM" -D --defined-only "$SO" | awk '{print $NF}')
  while read -r s; do
    grep -qx "$s" <<<"$DEFS" || { echo "错误：缺少导出 $s" >&2; fail=1; }
  done < <(grep -h '^//export ' "$ROOT"/mihomo-mobile/*.go | awk '{print $2}')
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
check-patches)
  export GOFLAGS=-mod=mod
  BUILD=${BUILD_DIR:-$ROOT/build/patch-check}
  for t in android ohos; do
    (
      patched_src "$BUILD/$t" "$t"
      while read -r patch mod targets; do
        [[ -z ${patch} || ${patch} == \#* ]] && continue
        [[ ,${targets}, == *,${t},* ]] || continue
        mapfile -t pkgs < <(sed -n 's#^+++ b/\(.*\)/[^/]*$#\1#p' "$ROOT/mihomo-mobile/patches/${patch}" | sort -u | sed "s#^#${mod}/#")
        echo "== ${t}：${patch} → ${pkgs[*]}"
        go vet -tags "$TAGS" "${pkgs[@]}"
        if [[ $t == android ]]; then
          # 只做类型检查（被改的包不依赖 cgo）；真正的 c-shared 由 CI android 作业用 NDK 构建。
          CGO_ENABLED=0 GOOS=android GOARCH=arm64 go vet -tags "$TAGS" "${pkgs[@]}"
        fi
        if grep -q '^+++ b/.*_test\.go$' "$ROOT/mihomo-mobile/patches/${patch}"; then
          # 补丁没打上时 -run Zephyr 匹配不到任何测试，go test 也会通过；所以要求跑到的 TestZephyr 数
          # 等于补丁里新增的 func TestZephyr 数，且全部 PASS。
          want=$(grep -c '^+func TestZephyr' "$ROOT/mihomo-mobile/patches/${patch}" || true)
          log=$(go test -count=1 -tags "$TAGS" -run Zephyr -v "${pkgs[@]}") || { echo "$log"; exit 1; }
          echo "$log"
          ran=$(grep -c '^=== RUN   TestZephyr' <<<"$log" || true)
          passed=$(grep -c '^--- PASS: TestZephyr' <<<"$log" || true)
          if [[ $want -lt 1 || $ran != "$want" || $passed != "$want" ]]; then
            echo "错误：${patch} 新增 ${want} 个 TestZephyr，实际运行 ${ran}、通过 ${passed}（补丁没打上？）" >&2; exit 1
          fi
        fi
      done < "$ROOT/mihomo-mobile/patches/series"
    )
  done
  echo "OK：补丁全部可打、vet 与补丁测试通过"
  ;;
verify-android-so)
  # 确认 Android libzmihomo.so 里真有 android-package-rules.patch 的代码（补丁里的错误字符串；
  # 补丁没进构建时 .so 不含它们，真机照旧 "read packages list: permission denied"）。CI 原生库缓存键含 tools/build-mihomo.sh 与 mihomo-mobile/**，命中的缓存必然来自跑过这道检查的构建。
  OUT=${2:-${OUT:-$ROOT/apps/android/core-engine/src/main/jniLibs}}
  [[ $OUT == /* ]] || OUT=$CALLER_PWD/$OUT
  sentinels=("android package list unavailable" "include-package/exclude-package need the Android package list")
  fail=0; n=0
  for so in "$OUT"/*/libzmihomo.so; do
    [[ -f $so ]] || continue; n=$((n+1))
    for str in "${sentinels[@]}"; do
      if LC_ALL=C grep -aqF "$str" "$so"; then echo "OK：$so 含「${str}」"
      else echo "错误：$so 不含「${str}」——android-package-rules.patch 没进构建" >&2; fail=1; fi
    done
  done
  [[ $n -gt 0 ]] || { echo "错误：$OUT 下没有 libzmihomo.so" >&2; exit 1; }
  [[ $fail == 0 ]] || exit 1
  echo "OK：$n 个 libzmihomo.so 都含 Android 包规则补丁哨兵"
  ;;
*) echo "用法：$0 android|ios|ohos|check-patches|verify-android-so [jniLibs 目录]"; exit 2;;
esac
