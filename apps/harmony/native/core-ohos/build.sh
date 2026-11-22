#!/usr/bin/env bash
# 构建 libcore_ohos.so（aarch64-unknown-linux-ohos，release）并做 check-ohos-so 校验。
# 用法：apps/harmony/native/core-ohos/build.sh   → 产物拷到 apps/harmony/native/out/arm64-v8a/libcore_ohos.so
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
NATIVE=$(cd "$HERE/.." && pwd)
source "$NATIVE/scripts/env.sh"
export PATH="$CARGO_HOME/bin:$PATH"

# 目标链接器：NDK 里的 aarch64-unknown-linux-ohos-clang 已带 --target/--sysroot/-fuse-ld=lld。
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_OHOS_LINKER=$OHOS_LLVM_BIN/aarch64-unknown-linux-ohos-clang
export CC_aarch64_unknown_linux_ohos=$OHOS_LLVM_BIN/aarch64-unknown-linux-ohos-clang
export AR_aarch64_unknown_linux_ohos=$OHOS_LLVM_BIN/llvm-ar

# 主机（build.rs / proc-macro）：没有系统 cc 时用 llvm19-root 的 clang + 该 root 做 sysroot（含 libc6-dev、libgcc-14-dev）。
# root 只有开发包、没有运行时库（libc.so 等链接脚本引用 /lib/.../libm.so.6、libgcc_s.so.1），
# 所以拼一个 sysroot：usr → llvm19-root/usr，lib → 主机 /lib（主机同为 Debian 13 / glibc 2.41）；
# --no-mmap-output-file：沙箱（gVisor）下 lld mmap 输出文件偶发 SIGBUS。
if ! command -v cc >/dev/null 2>&1; then
  R=${OHOS_LLVM_ROOT:-$OHOS_TOOLS/llvm19-root}
  W=$NATIVE/build/host-cc   # build/ 已 gitignore
  S=$NATIVE/build/host-sysroot
  mkdir -p "$W" "$S"
  ln -sfn "$R/usr" "$S/usr"
  ln -sfn /lib "$S/lib"
  cat >"$W/cc" <<EOW
#!/bin/sh
export LD_LIBRARY_PATH="$R/usr/lib/aarch64-linux-gnu:$R/usr/lib/llvm-19/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
exec "$R/usr/lib/llvm-19/bin/clang" --target=aarch64-linux-gnu --sysroot="$S" -fuse-ld=lld -L/lib/aarch64-linux-gnu -Wl,--no-mmap-output-file "\$@"
EOW
  chmod +x "$W/cc"
  export PATH="$W:$PATH"
  export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=$W/cc CC_aarch64_unknown_linux_gnu=$W/cc
fi

cd "$HERE"
cargo build --release --target aarch64-unknown-linux-ohos
# 尊重 CARGO_TARGET_DIR（沙箱里放 /tmp：/workspace 是 juicefs，lld 链接主机 build script 时偶发 SIGBUS）。
SO=${CARGO_TARGET_DIR:-$HERE/target}/aarch64-unknown-linux-ohos/release/libcore_ohos.so
mkdir -p "$NATIVE/out/arm64-v8a"
cp "$SO" "$NATIVE/out/arm64-v8a/libcore_ohos.so"
"$NATIVE/scripts/check-ohos-so.sh" --arch arm64 "$NATIVE/out/arm64-v8a/libcore_ohos.so"
