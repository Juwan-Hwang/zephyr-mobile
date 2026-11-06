#!/usr/bin/env bash
# 生成 UniFFI 绑定（Swift + Kotlin）。产物：core-mobile/bindings/{swift,kotlin}（入库，供 iOS/Android 直接引用，CI 校验不漂移）。
# 用法：tools/gen-bindings.sh [--check]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT/core-mobile"
export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$ROOT/core-mobile/target}
cargo build -q --lib
case "$(uname)" in Darwin) EXT=dylib;; *) EXT=so;; esac
LIB="$CARGO_TARGET_DIR/debug/libzephyr_mobile_core.$EXT"
OUT=$(mktemp -d)
for lang in swift kotlin; do
  cargo run -q --bin uniffi-bindgen -- generate --library "$LIB" --language $lang --out-dir "$OUT/$lang" --no-format
done
if [[ "${1:-}" == "--check" ]]; then
  diff -r "$OUT" bindings && echo "bindings up to date" || { echo "bindings 漂移：运行 tools/gen-bindings.sh"; exit 1; }
else
  rm -rf bindings && mv "$OUT" bindings && echo "bindings → core-mobile/bindings"
fi
