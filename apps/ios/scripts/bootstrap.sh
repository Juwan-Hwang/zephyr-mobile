#!/usr/bin/env bash
# 一键准备 iOS 工程：安装 XcodeGen → 生成 Zephyr.xcodeproj →（可选）打开 Xcode。
#   scripts/bootstrap.sh            生成并打开
#   scripts/bootstrap.sh --no-open  只生成（CI / 终端）
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null; then
  if ! command -v brew >/dev/null; then
    echo "需要 Homebrew：https://brew.sh" >&2; exit 1
  fi
  brew install xcodegen
fi

# 子模块（vendor/zephyr，tokens 来源）—— 只读，按需初始化。
git -C ../.. submodule update --init --recursive >/dev/null 2>&1 || true

# 图标缺失时补渲染。
if [ ! -f App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png ]; then
  scripts/render-icons.sh || echo "警告：图标渲染失败，Xcode 会提示缺少 AppIcon" >&2
fi

xcodegen generate --spec project.yml
echo "✓ 已生成 Zephyr.xcodeproj"

if [ "${1:-}" != "--no-open" ] && [ -z "${CI:-}" ]; then
  open Zephyr.xcodeproj
fi
