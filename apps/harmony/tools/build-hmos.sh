#!/bin/sh
# 用 HarmonyOS Command Line Tools（CLT 自带 hvigor + HarmonyOS SDK）无 DevEco 编 apps/harmony，
# 产出未签名 HAP；设了 ZEPHYR_SIGNING_DIR 时再调用私有签名仓库里的 sign-hap.sh 签名 + 校验。
# 项目原样构建（runtimeOS HarmonyOS、deviceTypes phone/tablet），只在临时副本里补 ohpm 依赖。
#
# 用法：
#   tools/build-hmos.sh                 前台（全量约 2–4 min，aarch64+qemu 更久）
#   tools/build-hmos.sh --bg            后台；然后 tools/build-hmos.sh --wait
#   tools/build-hmos.sh --summary       重新打印上次日志摘要
# 环境变量：
#   BUILD_MODE=release|debug（默认 release）  CLEAN=1 全量重编
#   HMOS_WORK_DIR  临时副本 + 日志目录（默认 $HMOS_TOOLS_DIR/work/hmos）
#   ZEPHYR_SIGNING_DIR  私有 zephyr-signing 克隆里含 sign-hap.sh 的目录（如 …/zephyr-signing/harmony）；
#                       不设则只出未签名 HAP。签名材料从不进本仓库。
#   SIGNED_HAP     签名输出路径（默认 $HMOS_WORK_DIR/zephyr-<mode>-signed.hap）
#   其余见 tools/env.sh（HMOS_TOOLS_DIR、CLT_DIR、JAVA、NODE、QEMU_X86、X86ROOT）
set -e
TOOLS=$(cd "$(dirname "$0")" && pwd)
. "$TOOLS/env.sh"
APP=$(cd "$TOOLS/.." && pwd)
: "${BUILD_MODE:=release}"
: "${HMOS_WORK_DIR:=$HMOS_TOOLS_DIR/work/hmos}"
PROJ=$HMOS_WORK_DIR/proj
LOG=$HMOS_WORK_DIR/hv.log
: "${SIGNED_HAP:=$HMOS_WORK_DIR/zephyr-$BUILD_MODE-signed.hap}"
SDK=$CLT_DIR/sdk/default
mkdir -p "$HMOS_WORK_DIR"

summary() {
  L=$HMOS_WORK_DIR/hv.clean.log
  sed 's/\x1b\[[0-9;]*m//g' "$LOG" > "$L"
  grep -E '^(> hvigor ERROR|[0-9]+ ERROR:|Error Message:|COMPILE RESULT|> hvigor WARN|[0-9]+ WARN:)' -A1 "$L" \
    | grep -v '^--$' | grep -v 'For details about ArkTS syntax' || true
  echo "----"
  grep -E 'COMPILE RESULT|BUILD (SUCCESSFUL|FAILED)|^rc=|^sign' "$L" || true
  ls -la "$PROJ"/entry/build/default/outputs/default/*.hap "$SIGNED_HAP" 2>/dev/null || true
}
case "$1" in
  --run-only) ;;
  --summary) summary; exit 0;;
  --wait) while ! grep -q '^rc=' "$LOG" 2>/dev/null; do sleep 5; done; summary; exit 0;;
  --bg)
    rm -f "$LOG"
    BUILD_MODE=$BUILD_MODE CLEAN=$CLEAN setsid nohup sh "$0" --run-only >/dev/null 2>&1 < /dev/null &
    echo "started in background; then: $0 --wait"; exit 0;;
esac

[ -d "$SDK/openharmony" ] && [ -d "$SDK/hms" ] || { echo "CLT not found at $CLT_DIR: run tools/fetch-clt.sh" >&2; exit 1; }
[ -n "$NODE" ] || { echo "node not found" >&2; exit 1; }
[ -n "$JAVA" ] || { echo "java (>=17) not found: run tools/fetch-host-deps.sh or set JAVA" >&2; exit 1; }

# 1. 非 x86_64 宿主：SDK 里的 x86_64 工具包 qemu（native/ 是 C++ 工具链，本项目不编 C++，不包）
sh "$TOOLS/wrap-x86.sh" $SDK/openharmony/toolchains $SDK/openharmony/ets $SDK/openharmony/js $SDK/hms/toolchains $SDK/hms/ets

# 2. 同步到临时副本（保留 entry/build、.hvigor 作增量缓存）
[ "$CLEAN" = 1 ] && rm -rf "$PROJ"
mkdir -p "$PROJ"
find "$PROJ" -mindepth 1 -maxdepth 1 ! -name entry ! -name .hvigor -exec rm -rf {} +
[ -d "$PROJ/entry" ] && find "$PROJ/entry" -mindepth 1 -maxdepth 1 ! -name build -exec rm -rf {} +
(cd "$APP" && tar cf - --exclude=./native --exclude=./tools --exclude=./docs --exclude=node_modules --exclude=oh_modules \
   --exclude=build --exclude=.hvigor --exclude=local.properties .) | (cd "$PROJ" && tar xf -)

# 3. ohpm install 的效果：唯一依赖是本地 file: 类型声明包（libcore_ohos.so）。
#    用软链模拟，避免 ohpm 去访问网络；缺了它 MobileCore 会被推成 any，报假的 arkts-no-any-unknown。
mkdir -p "$PROJ/entry/oh_modules"
ln -sfn ../src/main/cpp/types/libcore_ohos "$PROJ/entry/oh_modules/libcore_ohos.so"

run() {
  cd "$PROJ"
  export HMOS_X86_LD_PATH=$SDK/hms/toolchains/lib:$SDK/openharmony/toolchains/lib:$SDK/openharmony/previewer/common/bin
  export DEVECO_SDK_HOME=$CLT_DIR/sdk PATH=$(dirname "$JAVA"):$(dirname "$NODE"):$PATH
  rm -f "$LOG"
  set +e
  "$NODE" "$CLT_DIR/hvigor/bin/hvigorw.js" --mode module -p product=default -p buildMode="$BUILD_MODE" \
    assembleHap --no-daemon > "$LOG" 2>&1
  rc=$?
  set -e
  UNSIGNED=$PROJ/entry/build/default/outputs/default/entry-default-unsigned.hap
  if [ $rc = 0 ] && [ -n "$ZEPHYR_SIGNING_DIR" ] && [ -f "$UNSIGNED" ]; then
    echo "sign: $ZEPHYR_SIGNING_DIR/sign-hap.sh -> $SIGNED_HAP" >> "$LOG"
    # 签名在私有仓库的 sign-hap.sh 里（含 verify-app）。偶见 JVM SIGSEGV（139），重试一次。
    for try in 1 2; do
      rc=0
      JAVA=$JAVA SIGN_JAR=$SDK/openharmony/toolchains/lib/hap-sign-tool.jar \
        bash "$ZEPHYR_SIGNING_DIR/sign-hap.sh" "$UNSIGNED" "$SIGNED_HAP" >> "$LOG" 2>&1 || rc=$?
      [ $rc = 0 ] && break; echo "sign attempt $try rc=$rc" >> "$LOG"
    done
    echo "sign rc=$rc" >> "$LOG"
  fi
  echo "rc=$rc" >> "$LOG"
}
run
summary
