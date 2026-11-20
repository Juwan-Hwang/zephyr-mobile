# shellcheck shell=bash
# OHOS 原生工具链路径（M0）。可在调用前覆盖任一变量。
#   OHOS_TOOLS     工具根目录（setup-toolchain.sh 的安装位置）
#   OHOS_NDK_HOME  OpenHarmony native 目录（含 llvm/bin 与 sysroot）。
#                  x86_64/macOS 主机可直接指向 DevEco/命令行工具里的 sdk/default/openharmony/native；
#                  aarch64 Linux 主机用 setup-toolchain.sh 拼出的混合 NDK（Debian clang-19 + SDK sysroot）。
#   GO_OHOS_ROOT   go-patch 1.27.3（GOOS=openharmony）GOROOT
#   RUST_OHOS_HOME rustup/cargo 安装位置（RUSTUP_HOME/CARGO_HOME 的父目录）
OHOS_TOOLS=${OHOS_TOOLS:-/workspace/tools-ohos}
OHOS_NDK_HOME=${OHOS_NDK_HOME:-$OHOS_TOOLS/ohos-ndk-arm64}
GO_OHOS_ROOT=${GO_OHOS_ROOT:-$OHOS_TOOLS/go-ohos/go}
RUST_OHOS_HOME=${RUST_OHOS_HOME:-$OHOS_TOOLS/rust}
if [[ -d $RUST_OHOS_HOME/cargo && -z ${CARGO_HOME:-} ]]; then
  export RUSTUP_HOME=$RUST_OHOS_HOME/rustup CARGO_HOME=$RUST_OHOS_HOME/cargo
fi
[[ -n ${CARGO_HOME:-} ]] && PATH=$CARGO_HOME/bin:$PATH
OHOS_LLVM_BIN=$OHOS_NDK_HOME/llvm/bin
export OHOS_TOOLS OHOS_NDK_HOME GO_OHOS_ROOT OHOS_LLVM_BIN PATH
