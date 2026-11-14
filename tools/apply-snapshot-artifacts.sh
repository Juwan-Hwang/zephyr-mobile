#!/usr/bin/env bash
# 把 CI 手动重录（workflow_dispatch: record_ios_snapshots / record_android_snapshots）产出的快照 artifact
# 套用到本地工作区，供平台负责人审核后自行提交。本脚本只改工作区，不 add / commit。
#
# 用法：tools/apply-snapshot-artifacts.sh <run-id> [--ios] [--android] [--dark-only]
#   不给 --ios/--android 时两端都套用（artifact 不存在则跳过）。
#   --dark-only：只保留文件名属于深色变体的改动（iOS 名含 "dark"，Android 名含 "dark=true"），
#                其余改动还原，并列出被还原的文件，便于发现意料之外的变化。
# 依赖：gh（已登录）、git。
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUN=${1:?用法：tools/apply-snapshot-artifacts.sh <run-id> [--ios] [--android] [--dark-only]}
shift
IOS=0 ANDROID=0 DARK=0
for a in "$@"; do
  case "$a" in
    --ios) IOS=1 ;;
    --android) ANDROID=1 ;;
    --dark-only) DARK=1 ;;
    *) echo "未知参数：$a" >&2; exit 2 ;;
  esac
done
[[ $IOS == 0 && $ANDROID == 0 ]] && IOS=1 ANDROID=1

cd "$ROOT"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

IOS_DIR=apps/ios/SnapshotTests/__Snapshots__
ANDROID_DIR=apps/android   # artifact 内为 <module>/src/test/snapshots/images/...

apply() { # name dest
  local name=$1 dest=$2
  local err
  if ! err=$(gh run download "$RUN" -n "$name" -D "$TMP/$name" 2>&1 >/dev/null); then
    echo "跳过 $name（run $RUN）：${err:-下载失败}"; return 0
  fi
  cp -R "$TMP/$name/." "$dest/"
  echo "$name → $dest"
}

paths=()
[[ $IOS == 1 ]] && { apply ios-snapshots "$IOS_DIR"; paths+=("$IOS_DIR"); }
[[ $ANDROID == 1 ]] && { apply android-snapshots "$ANDROID_DIR"; paths+=("$ANDROID_DIR"); }

is_dark() { [[ "$1" == "$IOS_DIR"/* && "$(basename "$1")" == *dark* ]] || [[ "$1" == apps/android/* && "$(basename "$1")" == *dark=true* ]]; }

changed=() reverted=()
while IFS= read -r line; do
  f=${line:3}
  [[ "$f" == *.png ]] || continue
  if [[ $DARK == 1 ]] && ! is_dark "$f"; then
    if [[ "${line:0:2}" == "??" ]]; then rm -f -- "$f"; else git checkout -q -- "$f"; fi
    reverted+=("$f")
  else
    changed+=("$f")
  fi
done < <(git status --porcelain -- "${paths[@]}")

echo "改动 ${#changed[@]} 张："
for f in "${changed[@]+"${changed[@]}"}"; do echo "  $f"; done
if [[ ${#reverted[@]} -gt 0 ]]; then
  echo "已还原的非深色改动 ${#reverted[@]} 张（请确认是否预期）："
  for f in "${reverted[@]}"; do echo "  $f"; done
fi
echo "审核后自行 git add / commit；本脚本不提交。"
