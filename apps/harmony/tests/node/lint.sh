#!/bin/sh
# 与 ets-check/run.sh 相同的 ArkTS 严格模式禁用项正则，作用于任意给定 .ets 文件。
LINT=0
for f in "$@"; do
  if grep -nE ':\s*(any|unknown)\b|<(any|unknown)>|\bas (any|unknown)\b|\[\s*[a-zA-Z]+\s*:\s*(string|number)\s*\]\s*:|^\s*(const|let)\s*[\{\[]|=\s*/[^/*].*/[gimsuy]*[;,)]|\{\s*\.\.\.|\bvar\s|for\s*\(\s*(const|let)\s+\w+\s+in\s' "$f"; then
    echo "  ^ $f"; LINT=1
  fi
done
[ $LINT = 0 ] && echo "lint: 无"
exit $LINT
