#!/bin/sh
# apps/harmony 纯逻辑 .ets 的 node 侧检查（不需要 DevEco / HarmonyOS SDK）：
#   1. tsc --noEmit：把不含 @Entry / @Component 的 .ets 拷成 .ts，@kit.* 用 shims/ 下的最小声明；
#   2. ArkTS 严格模式禁用项扫描（engine/**，同 ets-check）；
#   3. 运行时测试：.out/rt = 拷贝 + rtstub/ 里的 @kit 运行时替身，用 node --experimental-transform-types 跑
#      cases/*.mjs（契约 fixtures、VPN 路由、指令解析等）和 model/*.mjs（页面背后的纯逻辑模型）。
# 用法：apps/harmony/tests/node/run.sh [过滤词]   首次会 npm ci（只装 typescript）。需要 node ≥ 22.7。
set -e
cd "$(dirname "$0")"
HERE=$(pwd)
REPO=${REPO:-$(cd ../../../.. && pwd)}; export REPO
SRC=$REPO/apps/harmony/entry/src/main/ets
OUT=$HERE/.out
FILTER=${1:-}
[ -x node_modules/typescript/bin/tsc ] || npm ci --silent --no-audit --no-fund

echo "== tsc"
rm -rf "$OUT" && mkdir -p "$OUT/t"
(cd "$SRC" && find . -name '*.ets') | while read -r f; do
  if grep -q '^@Entry\|^@Component\|^@ComponentV2\|^@CustomDialog' "$SRC/$f"; then continue; fi
  mkdir -p "$OUT/t/$(dirname "$f")"; cp "$SRC/$f" "$OUT/t/${f%.ets}.ts"
done
cat > "$OUT/tsconfig.json" <<J
{ "compilerOptions": { "target": "es2021", "module": "esnext", "moduleResolution": "bundler", "strict": true,
  "noEmit": true, "skipLibCheck": true, "lib": ["es2021"], "types": [],
  "paths": { "libcore_ohos.so": ["$REPO/apps/harmony/entry/src/main/cpp/types/libcore_ohos/index.d.ts"],
             "@kit.*": ["$HERE/shims/kit.*.d.ts"] } },
  "include": ["t/**/*.ts", "$HERE/shims/*.d.ts"] }
J
node node_modules/typescript/bin/tsc -p "$OUT/tsconfig.json"
echo "tsc ok"

echo "== ArkTS 严格模式禁用项（engine/**）"
sh ./lint.sh $(cd "$SRC" && find engine -name '*.ets' ! -path '*/native/*' | sed "s#^#$SRC/#")

echo "== 运行时测试"
cp -r "$OUT/t" "$OUT/rt" && cp rtstub/*.ts "$OUT/rt/"
for f in $(find "$OUT/rt" -name '*.ts'); do
  d=$(dirname "$f"); rel=$(realpath --relative-to="$d" "$OUT/rt")
  sed -i -e "s#from '\(\.[^']*\)'#from '\1.ts'#" \
    -e "s#from '@kit.CoreFileKit'#from '$rel/kit.CoreFileKit.ts'#" \
    -e "s#from '@kit.NetworkKit'#from '$rel/kit.NetworkKit.ts'#" \
    -e "s#from '@kit.\(AbilityKit\|BasicServicesKit\|PerformanceAnalysisKit\|AccessibilityKit\|SensorServiceKit\|ArkData\|ArkUI\)'#from '$rel/kit.Empty.ts'#" \
    -e "s/^import { BusinessError }/import type { BusinessError }/" -e "s/^import { Want }/import type { Want }/" \
    -e "s/^import { common, Want }/import type { common, Want }/" "$f"
done
node fix-imports.mjs "$OUT/rt"
FAIL=0
for t in cases/*.mjs model/*.mjs; do
  case "$t" in *"$FILTER"*) ;; *) continue ;; esac
  node --experimental-transform-types --no-warnings "$t" || { echo "  ^ $t"; FAIL=1; }
done
[ $FAIL = 0 ] && echo "all ok" || { echo "FAILED"; exit 1; }
