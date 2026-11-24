#!/usr/bin/env bash
# 16 KB 页大小模拟器加载测试（CI 任务 android-16k，非阻塞）。
#   load-test.sh build-probe <outdir>     用 NDK clang 编译 zm-dlopen（x86_64，16 KB 对齐）
#   load-test.sh run <apk> <probe>        在已启动的模拟器上：
#     1. getconf PAGE_SIZE 必须是 16384
#     2. adb install APK（安装器会拒绝未 16 KB 对齐的未压缩 .so）
#     3. 从 APK 取出本机 ABI 的全部 .so（必须含 libzmihomo.so 与 libzephyr_mobile_core.so），推到 /data/local/tmp 逐个 dlopen
#     4. 启动 LAUNCHER Activity，15 秒后进程必须还在，logcat 不得出现 dlopen failed / UnsatisfiedLinkError / 页大小相关错误
# 不改 apps/android：.so 是 App 惰性加载的（libzmihomo 在开 VPN 时才加载），所以第 3 步用独立探针直接 dlopen 同一份字节。
set -euo pipefail
cmd=${1:-}; shift || true

if [ "$cmd" = build-probe ]; then
  out=${1:?outdir}; mkdir -p "$out"
  ndk=${ANDROID_NDK_LATEST_HOME:-${ANDROID_NDK_HOME:-}}
  [ -n "$ndk" ] || ndk=$(ls -d "$ANDROID_HOME"/ndk/* | sort -V | tail -1)
  cc=$(ls "$ndk"/toolchains/llvm/prebuilt/*/bin/x86_64-linux-android28-clang | head -1)
  "$cc" -O2 -Wall -Wl,-z,max-page-size=16384 -o "$out/zm-dlopen" "$(dirname "$0")/zm-dlopen.c" -ldl
  file "$out/zm-dlopen" || true
  exit 0
fi

[ "$cmd" = run ] || { echo "usage: $0 build-probe <outdir> | run <apk> <probe>"; exit 2; }
apk=${1:?apk}; probe=${2:?probe}
PKG=${PKG:-com.juwanh.zephyr}
fail=0; err() { echo "::error::$*"; fail=1; }
adb wait-for-device

ps=$(adb shell getconf PAGE_SIZE | tr -d '\r')
abi=$(adb shell getprop ro.product.cpu.abi | tr -d '\r')
echo "PAGE_SIZE=$ps ABI=$abi SDK=$(adb shell getprop ro.build.version.sdk | tr -d '\r') KERNEL=$(adb shell uname -r | tr -d '\r')"
[ "$ps" = 16384 ] || { echo "::error::模拟器页大小是 $ps，不是 16384（镜像不是 ps16k）"; exit 1; }

echo "== install"
adb install -r -t "$apk" 2>&1 | tee /tmp/install.log
grep -q Success /tmp/install.log || err "APK 安装失败（16 KB 对齐问题会在这里报 INSTALL_FAILED_*）"

echo "== dlopen .so from APK (lib/$abi)"
tmp=$(mktemp -d); unzip -q -o "$apk" "lib/$abi/*" -d "$tmp" || true
ls -la "$tmp/lib/$abi" || true
for need in libzmihomo.so libzephyr_mobile_core.so; do
  [ -f "$tmp/lib/$abi/$need" ] || err "APK 里没有 lib/$abi/$need"
done
dev=/data/local/tmp/zm16k
adb shell "rm -rf $dev && mkdir -p $dev"
adb push "$tmp/lib/$abi/." "$dev/" >/dev/null
adb push "$probe" "$dev/zm-dlopen" >/dev/null
adb shell chmod 755 "$dev/zm-dlopen"
libs=$(cd "$tmp/lib/$abi" && ls *.so | sed "s#^#$dev/#" | tr '\n' ' ')
# 先加载依赖少的（Rust 核心、JNA），最后加载 Go c-shared 的 libzmihomo
out=$(adb shell "cd $dev && LD_LIBRARY_PATH=$dev ./zm-dlopen $libs; echo EXIT=\$?" | tr -d '\r')
echo "$out"
echo "$out" | grep -q '^EXIT=0$' || err "有 .so 在 16 KB 页上 dlopen 失败"
for need in libzmihomo.so libzephyr_mobile_core.so; do
  echo "$out" | grep -q "^OK   $dev/$need" || err "$need 未加载成功"
done

adb shell rm -rf "$dev"
echo "MemTotal: $(adb shell grep MemTotal /proc/meminfo | tr -d '\r')"
echo "== launch app"
adb logcat -c || true
# namespace 与 applicationId 不同，按 LAUNCHER 解析组件名，不写死类名
comp=$(adb shell cmd package resolve-activity --brief -c android.intent.category.LAUNCHER "$PKG" | tr -d '\r' | tail -1)
echo "launcher: $comp"
case $comp in "$PKG"/*) ;; *) err "解析不到 $PKG 的启动 Activity";; esac
adb shell am start -W -n "$comp" | tr -d '\r' | tee /tmp/am.txt || true
grep -q "^Status: ok" /tmp/am.txt || err "启动 Activity 失败"
sleep 15
pid=$(adb shell pidof "$PKG" | tr -d '\r' || true)
if [ -z "$pid" ]; then
  err "启动 15 秒后进程 $PKG 不在了"
  adb logcat -d | grep -E "lowmemorykiller: Kill '$PKG'" && echo "::warning::进程是被 lowmemorykiller 杀的（模拟器内存不足，属基础设施问题，不是 .so 加载失败）"
fi
adb logcat -d > /tmp/logcat.txt || true
# 只看本 App：进程内日志 + 提到包名的系统日志（排除系统自带 App 的 nativeloader 噪音）
{ [ -n "$pid" ] && adb logcat -d --pid="$pid"; grep -F "$PKG" /tmp/logcat.txt; } > /tmp/applog.txt 2>/dev/null || true
echo "（本 App 相关日志 $(wc -l < /tmp/applog.txt) 行）"
if grep -E "dlopen failed|UnsatisfiedLinkError|not page-aligned|PageSizeMismatch|page size compat|16 ?KB compat|Process: $PKG, PID" /tmp/applog.txt | grep -v "zm-dlopen" > /tmp/bad.txt; then
  cat /tmp/bad.txt; err "logcat 有原生库加载 / 页大小相关错误"
fi
grep -E "AndroidRuntime|Fatal signal" /tmp/applog.txt | head -40 || true
if [ -n "$pid" ]; then
  echo "== $PKG 进程已映射的 App .so（惰性加载，未开 VPN 时可能为空，仅供参考）"
  adb shell run-as "$PKG" cat /proc/"$pid"/maps 2>/dev/null | grep -oE '[^ /]+\.so$' | sort -u | grep -E 'zmihomo|zephyr|jnidispatch' || echo "(无)"
fi
[ $fail = 0 ] && echo "16 KB load test PASSED" || echo "16 KB load test FAILED"
exit $fail
