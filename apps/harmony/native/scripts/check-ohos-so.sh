#!/usr/bin/env bash
# 校验一个给 OHOS 用的 .so：
#   1) 没有 initial-exec/local-exec TLS 重定位（musl 拒绝 dlopen 这类库）：
#      arm64 禁 R_AARCH64_TLS_TPREL* / R_AARCH64_TLSLE_* / R_AARCH64_TLSIE_*；x86_64 禁 R_X86_64_TPOFF* / GOTTPOFF。
#      允许 TLSDESC / TLSGD / DTPMOD/DTPREL（general-dynamic）。思路同 ArkClash build-core.sh 的构建后检查（自写实现）。
#   2) 打印 PT_TLS 段（有则显示其大小，供人工核对：动态 TLS 下 musl 可以接受）。
#   3) 期望的导出符号全部存在（--expect "a b c" 或 --expect-file 每行一个）。
#   4) DT_NEEDED 只能是 OHOS 上存在的库：sysroot/usr/lib/<triple>/ 下的 .so，
#      或 --allow 列出的随包库（如 libc++_shared.so）。
# 用法：check-ohos-so.sh [--arch arm64|amd64] [--expect "..."] [--allow "..."] lib.so
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
source "$HERE/env.sh"
ARCH=arm64 EXPECT="" ALLOW=""
while [[ $# -gt 1 ]]; do
  case $1 in
    --arch) ARCH=$2; shift 2;;
    --expect) EXPECT="$EXPECT $2"; shift 2;;
    --expect-file) EXPECT="$EXPECT $(grep -v '^#' "$2" | tr '\n' ' ')"; shift 2;;
    --allow) ALLOW="$ALLOW $2"; shift 2;;
    *) echo "未知参数 $1" >&2; exit 2;;
  esac
done
SO=$1
case $ARCH in
  arm64) TRIPLE=aarch64-linux-ohos; BAD='R_AARCH64_(TLS_TPREL|TLSLE_|TLSIE_)';;
  amd64) TRIPLE=x86_64-linux-ohos; BAD='R_X86_64_(TPOFF|GOTTPOFF)';;
  *) echo "不支持的 arch $ARCH" >&2; exit 2;;
esac
RE=$OHOS_LLVM_BIN/llvm-readelf
NM=$OHOS_LLVM_BIN/llvm-nm
fail=0
echo "== $SO ($(stat -c %s "$SO") 字节)"
# 先读进变量再 grep，避免 grep -q 提前退出 + pipefail 误判（ArkClash 记录过的坑）。
RELOCS=$("$RE" -rW "$SO")
TLSREL=$(grep -oE 'R_(AARCH64|X86_64)_[A-Z0-9_]*(TLS|TPREL|TPOFF|DTP)[A-Z0-9_]*' <<<"$RELOCS" | sort | uniq -c || true)
echo "-- TLS 相关重定位："; echo "${TLSREL:-  （无）}"
if grep -Eq "$BAD" <<<"$RELOCS"; then echo "FAIL: 存在 initial-exec/local-exec TLS 重定位（$BAD）"; fail=1; else echo "OK: 无 ${BAD}"; fi
echo "-- PT_TLS："; "$RE" -lW "$SO" | grep -E '^\s*TLS' || echo "  （无 PT_TLS 段）"
FLAGS=$("$RE" -dW "$SO" | grep -E 'FLAGS' || true)
if grep -q STATIC_TLS <<<"$FLAGS"; then echo "FAIL: DF_STATIC_TLS 置位"; fail=1; else echo "OK: 无 DF_STATIC_TLS"; fi
echo "-- DT_NEEDED："
SYSLIB=$OHOS_NDK_HOME/sysroot/usr/lib/$TRIPLE
for n in $("$RE" -dW "$SO" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p'); do
  if [[ -e $SYSLIB/$n ]]; then echo "  $n （系统库，sysroot 有）"
  elif [[ " $ALLOW " == *" $n "* ]]; then echo "  $n （随包库，--allow）"
  else echo "  $n FAIL: OHOS sysroot 里没有，也不在 --allow"; fail=1; fi
done
SONAME=$("$RE" -dW "$SO" | sed -n 's/.*(SONAME).*\[\(.*\)\]/\1/p'); echo "-- SONAME: ${SONAME:-（无）}"
if [[ -n ${EXPECT// /} ]]; then
  DEFS=$("$NM" -D --defined-only "$SO" | awk '{print $NF}')
  miss=""; for s in $EXPECT; do grep -qx "$s" <<<"$DEFS" || miss="$miss $s"; done
  if [[ -n $miss ]]; then echo "FAIL: 缺少导出符号:$miss"; fail=1; else echo "OK: 期望导出全部存在（$(wc -w <<<"$EXPECT") 个）"; fi
fi
[[ $fail == 0 ]] && echo "PASS" || { echo "CHECK FAILED"; exit 1; }
