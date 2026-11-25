#!/bin/bash
# 构建期把固定版本的 mihomo 地理数据（geoip.metadb + GeoSite.dat）打进 PacketTunnel.appex/geodata/。
# 由 project.yml 里 PacketTunnel 的 preBuildScripts 调用（docs/geodata.md、契约 §20；与 Android f1b8930 的 bundleGeodataAssets 同构）。
#
#   - 拉取 / 校验交给 tools/fetch-geodata.sh（按 tools/geodata.lock 的 sha256；缓存在仓库根 build/geodata，已在且哈希一致不重下）。
#   - Release：拉不到即构建失败（发出去的包必须带地理数据，否则大陆首连会卡在下载上）。
#   - Debug：只告警并继续（扩展首次连接时由 mihomo-mobile 有界下载 15 s，失败报 `geodata missing:`），下次构建再试。
#   - 只拷 lock 里列出的文件名；目标目录里多余的旧文件删掉。
# 扩展启动时（BundledGeodata）把内核目录里还没有的文件拷过去，从不覆盖已有文件。
set -uo pipefail

ROOT="${SRCROOT:?}/../.."
LOCK="$ROOT/tools/geodata.lock"
CACHE="$ROOT/build/geodata"
DEST="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/geodata"

fail() {
  if [ "${CONFIGURATION:-Debug}" = "Release" ]; then
    echo "error: 地理数据：$1（Release 必须打包地理数据，见 docs/geodata.md）"
    exit 1
  fi
  echo "warning: 地理数据：$1（Debug 继续构建：扩展首次连接时有界下载，失败会报 geodata missing）"
  exit 0
}

[ -f "$LOCK" ] || fail "找不到 $LOCK"
"$ROOT/tools/fetch-geodata.sh" "$CACHE" || fail "tools/fetch-geodata.sh 失败（网络或 sha256 不符）"

mkdir -p "$DEST" || fail "无法创建 $DEST"
names=()
while read -r name hash url; do
  [[ -z "${name:-}" || "$name" == \#* ]] && continue
  [ -f "$CACHE/$name" ] || fail "缓存里没有 $name"
  # cmp 相同就不再拷：增量构建不改动产物时间戳。
  if ! cmp -s "$CACHE/$name" "$DEST/$name"; then
    cp -f "$CACHE/$name" "$DEST/$name.tmp" && mv -f "$DEST/$name.tmp" "$DEST/$name" || fail "拷贝 $name 失败"
  fi
  names+=("$name")
done <"$LOCK"
[ ${#names[@]} -gt 0 ] || fail "geodata.lock 里没有文件"

for f in "$DEST"/*; do
  [ -e "$f" ] || continue
  keep=0
  for n in "${names[@]}"; do [ "$(basename "$f")" = "$n" ] && keep=1; done
  [ $keep = 1 ] || rm -f "$f"
done
echo "地理数据 → $DEST（${names[*]}）"
