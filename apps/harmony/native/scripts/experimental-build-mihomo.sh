#!/usr/bin/env bash
# 把 mihomo-mobile/（只读引用，不改其源码）编成 OHOS 用的 c-shared libzmihomo.so。
#   build-ohos-mihomo.sh [arm64|amd64]       → apps/harmony/native/out/<abi>/libzmihomo.so
#   build-ohos-mihomo.sh --probe [arm64]     → 只编一个同参数的最小 c-shared 测试库（验证工具链与 TLS 检查）
# 工具链：go-patch go1.27.3（GOOS=openharmony，SHA256 钉死，见 setup-toolchain.sh）+ OHOS clang/sysroot。
# gVisor：OHOS 的 SELinux 不允许对系统 VPN 交来的 TUN fd 做 fstat，fdbased.IsSocketFD 会失败。
#   做法：在构建目录里复制 mihomo-mobile 的 go.mod/go.sum + 源码，把 metacubex/gvisor 拷出来打
#   patches/gvisor-fstat-tun.patch，再用 go mod edit -replace 指过去。仓库内 mihomo-mobile/go.mod 不变。
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
source "$HERE/env.sh"
PROBE=0; [[ ${1:-} == --probe ]] && { PROBE=1; shift; }
ARCH=${1:-arm64}
case $ARCH in
  arm64) ABI=arm64-v8a;;
  amd64) ABI=x86_64;;
  *) echo "用法：$0 [--probe] [arm64|amd64]" >&2; exit 2;;
esac
GO=$GO_OHOS_ROOT/bin/go
[[ -x $GO ]] || { echo "缺 go-patch：$GO_OHOS_ROOT（先跑 setup-toolchain.sh）" >&2; exit 1; }
[[ -x $OHOS_LLVM_BIN/clang ]] || { echo "缺 OHOS clang：$OHOS_LLVM_BIN" >&2; exit 1; }
export GOROOT=$GO_OHOS_ROOT GOTOOLCHAIN=local GOFLAGS=-mod=mod
export GOOS=openharmony GOARCH=$ARCH CGO_ENABLED=1
export CC="$GOROOT/ohos-scripts/cc-$ARCH" CXX="$GOROOT/ohos-scripts/cxx-$ARCH" AR="$OHOS_LLVM_BIN/llvm-ar"
# 动态 TLS：C 侧 TLS 用 general-dynamic（musl dlopen 安全）。上游 clang 对 OHOS 默认 emutls，二者都可被 dlopen。
export CGO_CFLAGS="-O2 -g0 -ftls-model=global-dynamic"
export GOMODCACHE=${GOMODCACHE:-$OHOS_TOOLS/gopath/pkg/mod}
export GOCACHE=${GOCACHE:-$HOME/.cache/go-build-ohos}
BUILD=${BUILD_DIR:-$ROOT/apps/harmony/native/build/go-$ARCH}
OUT=${OUT:-$ROOT/apps/harmony/native/out/$ABI}
mkdir -p "$BUILD" "$OUT"
TAGS="with_gvisor"   # 与 Android/iOS 一致；不加 netgo（用 cgo resolver 走系统 DNS 配置）
LDFLAGS="-s -w -buildid="
"$GO" version

if [[ $PROBE == 1 ]]; then
  P=$BUILD/probe; rm -rf "$P"; mkdir -p "$P"
  cat > "$P/go.mod" <<'GOMOD'
module zprobe
go 1.27
GOMOD
  cat > "$P/main.go" <<'GOSRC'
package main

// #include <stdlib.h>
// static __thread int ctls;
// static int bump(void) { return ++ctls; }
import "C"
import (
	"net"
	"runtime"
	"sync"
	"unsafe"
)

var mu sync.Mutex

//export zm_version
func zm_version() *C.char { return C.CString("probe " + runtime.Version() + " " + runtime.GOOS + "/" + runtime.GOARCH) }

//export zm_probe
func zm_probe() C.int {
	mu.Lock()
	defer mu.Unlock()
	ch := make(chan int)
	go func() { ch <- int(C.bump()) }()
	_, _ = net.ResolveIPAddr("ip", "localhost")
	return C.int(<-ch)
}

//export zm_free
func zm_free(p *C.char) { C.free(unsafe.Pointer(p)) }

func main() {}
GOSRC
  (cd "$P" && "$GO" build -trimpath -tags "$TAGS" -ldflags "$LDFLAGS -extldflags=-Wl,-soname,libzprobe.so" -buildmode=c-shared -o "$OUT/libzprobe.so" .)
  rm -f "$OUT/libzprobe.h"
  "$HERE/check-ohos-so.sh" --arch "$ARCH" --expect "zm_version zm_probe zm_free" "$OUT/libzprobe.so"
  exit 0
fi

SRC=$BUILD/src; rm -rf "$SRC"; mkdir -p "$SRC"
cp "$ROOT"/mihomo-mobile/go.mod "$ROOT"/mihomo-mobile/go.sum "$SRC/"
find "$ROOT/mihomo-mobile" -maxdepth 1 -name '*.go' ! -name '*_test.go' -exec cp {} "$SRC/" \;
cd "$SRC"
GV_VER=$("$GO" list -m -f '{{.Version}}' github.com/metacubex/gvisor)
"$GO" mod download github.com/metacubex/gvisor
GV_DIR=$("$GO" list -m -f '{{.Dir}}' github.com/metacubex/gvisor)
PG=$BUILD/gvisor-patched
if [[ ! -f $PG/.zephyr-patch-$GV_VER ]] || ! cmp -s "$HERE/patches/gvisor-fstat-tun.patch" "$PG/.zephyr-patch-$GV_VER"; then
  rm -rf "$PG"; cp -R "$GV_DIR" "$PG"; chmod -R u+w "$PG"
  (cd "$PG" && git apply -p1 --unsafe-paths "$HERE/patches/gvisor-fstat-tun.patch")
  cp "$HERE/patches/gvisor-fstat-tun.patch" "$PG/.zephyr-patch-$GV_VER"
fi
"$GO" mod edit -replace="github.com/metacubex/gvisor=$PG"
MIHOMO_VER=$("$GO" list -m -f '{{.Version}}' github.com/metacubex/mihomo)
echo "mihomo $MIHOMO_VER, gvisor $GV_VER（已打 fstat 补丁）"
time "$GO" build -trimpath -tags "$TAGS" \
  -ldflags "$LDFLAGS -X github.com/metacubex/mihomo/constant.Version=$MIHOMO_VER -extldflags=-Wl,-soname,libzmihomo.so" \
  -buildmode=c-shared -o "$OUT/libzmihomo.so" .
mv -f "$OUT/libzmihomo.h" "$BUILD/libzmihomo.h"
EXPECT=$(grep -h '^//export ' "$ROOT"/mihomo-mobile/*.go | awk '{print $2}' | tr '\n' ' ')
"$HERE/check-ohos-so.sh" --arch "$ARCH" --expect "$EXPECT" "$OUT/libzmihomo.so"
