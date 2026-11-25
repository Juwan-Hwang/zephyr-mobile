#!/usr/bin/env bash
# 拉取固定版本的 mihomo 地理数据（geoip.metadb + GeoSite.dat），按 tools/geodata.lock 校验 sha256。
# 产物给平台层打进安装包，首次启动拷进 zm_start 的 home_dir，内核启动就不必联网下载（docs/geodata.md）。
# 用法：
#   tools/fetch-geodata.sh [输出目录]     默认 build/geodata；已存在且哈希一致的文件不重下
#   tools/fetch-geodata.sh --update       只打印上游 latest 的文件哈希（更新快照用，不写文件）
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOCK=$ROOT/tools/geodata.lock
UPSTREAM=https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest

sha() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

if [[ "${1:-}" == "--update" ]]; then
  for f in geoip.metadb geosite.dat; do
    printf '%s ' "$f"; curl -fsSL --retry 3 "$UPSTREAM/$f.sha256sum"
  done
  exit 0
fi

OUT=${1:-$ROOT/build/geodata}
mkdir -p "$OUT"
while read -r name hash url; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  dst=$OUT/$name
  if [[ -f "$dst" && "$(sha "$dst")" == "$hash" ]]; then echo "ok   ${name}（已存在）"; continue; fi
  curl -fsSL --retry 3 --connect-timeout 20 -o "$dst.part" "$url"
  got=$(sha "$dst.part")
  if [[ "$got" != "$hash" ]]; then
    rm -f "$dst.part"; echo "sha256 不符：$name 期望 $hash 实得 ${got}（${url}）" >&2; exit 1
  fi
  mv "$dst.part" "$dst"
  echo "ok   $name $(wc -c <"$dst" | tr -d ' ') B"
done <"$LOCK"
echo "地理数据 → $OUT"
