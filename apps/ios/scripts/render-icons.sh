#!/usr/bin/env bash
# 重新生成 App 图标（design/prototype/brand/app-icon.svg → App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png）。
set -euo pipefail
cd "$(dirname "$0")"
if ! python3 -c 'import cairosvg' 2>/dev/null && ! command -v rsvg-convert >/dev/null; then
  if command -v brew >/dev/null; then brew install librsvg; else python3 -m pip install --user cairosvg; fi
fi
python3 render_icons.py
