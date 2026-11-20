#!/bin/sh
# 下载 OpenHarmony 6.1-Release 公开 SDK（API 23）linux 部分，只给 build-ohos-check.sh 用（快速 ArkTS 编译检查）。
set -e
. "$(dirname "$0")/env.sh"
URL=https://repo.huaweicloud.com/openharmony/os/6.1-Release/ohos-sdk-windows_linux-public.tar.gz
SHA=b833b75a64ee46bbd7880921abbb49b733ec5c8171b6684c9b524d57f624cee0
[ -d "$OH_SDK_DIR/ets" ] && { echo "already at $OH_SDK_DIR"; exit 0; }
mkdir -p "$HMOS_TOOLS_DIR/dl" "$OH_SDK_DIR"
F=$HMOS_TOOLS_DIR/dl/ohos-sdk-6.1-Release-public.tar.gz
[ -f "$F" ] || { curl -fL --retry 3 -o "$F.part" "$URL"; mv "$F.part" "$F"; }
echo "$SHA  $F" | sha256sum -c -
T=$(mktemp -d); tar -xzf "$F" -C "$T" --wildcards '*linux/*'
for z in "$T"/linux/*.zip; do unzip -q -o "$z" -d "$OH_SDK_DIR"; done
rm -rf "$T"; ls "$OH_SDK_DIR"
