#!/bin/sh
# 快速 ArkTS 编译检查：npm 上的 hvigor 6.26.20 + OpenHarmony 6.1 公开 SDK（API 23）。
# 比 build-hmos.sh 依赖少（不需要 HarmonyOS CLT），但只能验证 OpenHarmony 范围内的 API：
# 临时副本里改 runtimeOS→OpenHarmony、deviceTypes phone→default（OH SDK 无 phone syscap 集），产物不能上架/真机装。
# 发布 / 云调试用 tools/build-hmos.sh。
# 用法：同 build-hmos.sh（--bg / --wait / --summary，CLEAN=1）；HMOS_WORK_DIR 默认 $HMOS_TOOLS_DIR/work/ohos-check
set -e
TOOLS=$(cd "$(dirname "$0")" && pwd)
. "$TOOLS/env.sh"
APP=$(cd "$TOOLS/.." && pwd)
: "${HVIGOR_NPM_VERSION:=6.26.20}"
: "${HMOS_WORK_DIR:=$HMOS_TOOLS_DIR/work/ohos-check}"
HV=$HMOS_TOOLS_DIR/hvigor-npm-$HVIGOR_NPM_VERSION
SDKL=$HMOS_WORK_DIR/sdk
PROJ=$HMOS_WORK_DIR/proj
LOG=$HMOS_WORK_DIR/hv.log
mkdir -p "$HMOS_WORK_DIR"

summary() {
  L=$HMOS_WORK_DIR/hv.clean.log
  sed 's/\x1b\[[0-9;]*m//g' "$LOG" > "$L"
  grep -E '^(> hvigor ERROR|[0-9]+ ERROR:|Error Message:|COMPILE RESULT|> hvigor WARN|[0-9]+ WARN:)' -A1 "$L" \
    | grep -v '^--$' | grep -v 'For details about ArkTS syntax' || true
  echo "----"
  grep -E 'COMPILE RESULT|BUILD (SUCCESSFUL|FAILED)|^rc=' "$L" || true
  ls -la "$PROJ"/entry/build/default/outputs/default/*.hap 2>/dev/null || echo "(no .hap)"
}
case "$1" in
  --run-only) ;;
  --summary) summary; exit 0;;
  --wait) while ! grep -q '^rc=' "$LOG" 2>/dev/null; do sleep 5; done; summary; exit 0;;
  --bg)
    rm -f "$LOG"
    CLEAN=$CLEAN setsid nohup sh "$0" --run-only >/dev/null 2>&1 < /dev/null &
    echo "started in background; then: $0 --wait"; exit 0;;
esac

[ -d "$OH_SDK_DIR/ets" ] || { echo "OpenHarmony SDK not found at $OH_SDK_DIR: run tools/fetch-oh-sdk.sh" >&2; exit 1; }
# 1. hvigor（npm，源 repo.harmonyos.com）
if [ ! -d "$HV/node_modules/@ohos/hvigor" ]; then
  mkdir -p "$HV"; cd "$HV"
  echo "registry=https://repo.harmonyos.com/npm/" > .npmrc
  printf '{"name":"hv","private":true,"dependencies":{"@ohos/hvigor":"%s","@ohos/hvigor-ohos-plugin":"%s"}}\n' \
    "$HVIGOR_NPM_VERSION" "$HVIGOR_NPM_VERSION" > package.json
  npm install --no-audit --no-fund
fi
# 2. SDK 布局：hvigor 要 <sdk.dir>/<api>/<component>/oh-uni-package.json（js、previewer 缺了会报 license 未接受）
mkdir -p "$SDKL/23"
for d in ets js toolchains native previewer; do ln -sfn "$OH_SDK_DIR/$d" "$SDKL/23/$d"; done
sh "$TOOLS/wrap-x86.sh" "$OH_SDK_DIR/toolchains" "$OH_SDK_DIR/ets" "$OH_SDK_DIR/js"

# 3. 同步临时副本（保留 entry/build、.hvigor 作增量缓存）
[ "$CLEAN" = 1 ] && rm -rf "$PROJ"
mkdir -p "$PROJ"
find "$PROJ" -mindepth 1 -maxdepth 1 ! -name entry ! -name .hvigor -exec rm -rf {} +
[ -d "$PROJ/entry" ] && find "$PROJ/entry" -mindepth 1 -maxdepth 1 ! -name build -exec rm -rf {} +
(cd "$APP" && tar cf - --exclude=./native --exclude=./tools --exclude=./docs --exclude=node_modules --exclude=oh_modules \
   --exclude=build --exclude=.hvigor --exclude=local.properties .) | (cd "$PROJ" && tar xf -)

# 4. 只在副本里的改动
cd "$PROJ"
python3 - <<'P'
import re
p='build-profile.json5'; s=open(p).read()
s=re.sub(r'"targetSdkVersion":\s*"[^"]*",\s*\n','',s)
s=re.sub(r'"compatibleSdkVersion":\s*"[^"]*"','"compileSdkVersion": 23,\n        "compatibleSdkVersion": 23',s)
s=s.replace('"runtimeOS": "HarmonyOS"','"runtimeOS": "OpenHarmony"')
open(p,'w').write(s)
p='entry/src/main/module.json5'; s=open(p).read()
s=re.sub(r'"phone"','"default"',s,count=1)
open(p,'w').write(s)
P
echo "sdk.dir=$SDKL" > local.properties
ln -sfn "$HV/node_modules" node_modules
mkdir -p entry/oh_modules
ln -sfn ../src/main/cpp/types/libcore_ohos entry/oh_modules/libcore_ohos.so

# 5. assembleHap（debug，未签名）
cd "$PROJ"
export OHOS_BASE_SDK_HOME=$SDKL PATH=$(dirname "$JAVA"):$PATH
export HMOS_X86_LD_PATH=$OH_SDK_DIR/toolchains/lib:$OH_SDK_DIR/previewer/common/bin
rm -f "$LOG"
set +e
"$NODE" node_modules/@ohos/hvigor/bin/hvigor.js --mode module -p product=default -p buildMode=debug \
  assembleHap --no-daemon > "$LOG" 2>&1
echo "rc=$?" >> "$LOG"
summary
