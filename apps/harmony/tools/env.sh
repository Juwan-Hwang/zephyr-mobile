# shellcheck shell=sh
# 公共环境（被其余脚本 source）。全部可用环境变量覆盖；不含任何签名材料。
# HMOS_TOOLS_DIR：放下载物（CLT / OH SDK / qemu / x86 sysroot / JRE）的目录，体积约 10 GB，勿放进仓库。
TOOLS_SRC=$(cd "$(dirname "${0}")" 2>/dev/null && pwd)
: "${HMOS_TOOLS_DIR:=${XDG_CACHE_HOME:-$HOME/.cache}/zephyr-harmony-tools}"
# HarmonyOS Command Line Tools（含 HarmonyOS SDK = openharmony + hms）
: "${CLT_VERSION:=6.1.1.280}"
: "${CLT_DIR:=$HMOS_TOOLS_DIR/clt/$CLT_VERSION/command-line-tools}"
# OpenHarmony 公开 SDK（只给 build-ohos-check.sh 用）
: "${OH_SDK_DIR:=$HMOS_TOOLS_DIR/oh-sdk-6.1/linux}"
# 宿主不是 x86_64 时：qemu-user + amd64 sysroot 跑 SDK 里的 x86_64 工具
: "${QEMU_X86:=}"
: "${X86ROOT:=$HMOS_TOOLS_DIR/x86root}"
if [ -z "$QEMU_X86" ]; then
  if [ -x "$HMOS_TOOLS_DIR/qemu/usr/bin/qemu-x86_64" ]; then QEMU_X86=$HMOS_TOOLS_DIR/qemu/usr/bin/qemu-x86_64
  else QEMU_X86=$(command -v qemu-x86_64 || command -v qemu-x86_64-static || true); fi
fi
# Java ≥17（app_packing_tool.jar / hap-sign-tool.jar）
if [ -z "$JAVA" ]; then
  for j in "$HMOS_TOOLS_DIR"/jdk/usr/lib/jvm/java-*-openjdk-*/bin/java; do [ -x "$j" ] && JAVA=$j; done
  [ -z "$JAVA" ] && JAVA=$(command -v java || true)
fi
# Node（hvigor）：优先宿主 node（aarch64 上 CLT 自带的 x86_64 node 只能 qemu 跑，慢）
: "${NODE:=$(command -v node || true)}"
HOST_ARCH=$(uname -m)
export HMOS_TOOLS_DIR CLT_VERSION CLT_DIR OH_SDK_DIR QEMU_X86 X86ROOT JAVA NODE HOST_ARCH
