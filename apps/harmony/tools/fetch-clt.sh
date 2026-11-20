#!/bin/sh
# 下载并解压 HarmonyOS Command Line Tools（linux-x64；含 hvigor、ohpm、HarmonyOS SDK = openharmony + hms）。
# 官方下载中心（developer.huawei.com/consumer/cn/download/）的链接需登录且带会话签名，不能 curl；
# 这里用公开镜像并校验 sha256（镜像内容与官方包一致性无法独立证明，见 docs/BUILD-NO-DEVECO.md）。
# 用法：tools/fetch-clt.sh [版本]      （默认 $CLT_VERSION = 6.1.1.280）
set -e
. "$(dirname "$0")/env.sh"
V=${1:-$CLT_VERSION}
DEST=$HMOS_TOOLS_DIR/clt/$V
case "$V" in
  6.1.1.280)  # HarmonyOS 6.1.1 Release SDK（API 24）；github.com/ErBWs/ohos-sdk 的 release（tar.gz 拆成两段）
    B=https://github.com/ErBWs/ohos-sdk/releases/download/6.1.1.280/ohos-sdk-linux-amd64.tar.gz
    PARTS="aa ab"; SHA=3d37eb5a3a81358a9731c35265f4f29d8ecf1028b0bbbb777f2928cd6990aa83; KIND=tgz;;
  6.0.1.251)  # HarmonyOS 6.0.1 SDK（API 21）；Hugging Face 镜像
    B=https://huggingface.co/csukuangfj/harmonyos-commandline-tools/resolve/main/commandline-tools-linux-x64-6.0.1.251.zip
    PARTS=""; SHA=e971348eabe959b41b1d07fae037b3cc53ab2c0a8306f0895357dd45f98ad421; KIND=zip;;
  *) echo "unknown CLT version $V (known: 6.1.1.280, 6.0.1.251)" >&2; exit 1;;
esac
if [ -f "$DEST/command-line-tools/version.txt" ]; then echo "already at $DEST"; cat "$DEST/command-line-tools/version.txt"; exit 0; fi
mkdir -p "$HMOS_TOOLS_DIR/dl" "$DEST"
cd "$HMOS_TOOLS_DIR/dl"
F=clt-$V.$KIND
if [ ! -f "$F" ]; then
  if [ -n "$PARTS" ]; then
    rm -f "$F.part"; for p in $PARTS; do curl -fL --retry 3 -o "$F.$p" "$B.$p"; cat "$F.$p" >> "$F.part"; rm -f "$F.$p"; done
  else curl -fL --retry 3 -o "$F.part" "$B"; fi
  mv "$F.part" "$F"
fi
echo "$SHA  $F" | sha256sum -c -
if [ "$KIND" = zip ]; then unzip -q "$F" -d "$DEST"; else tar -xzf "$F" -C "$DEST"; fi
cat "$DEST/command-line-tools/version.txt"
echo "CLT_DIR=$DEST/command-line-tools   （可删 $HMOS_TOOLS_DIR/dl/$F 省空间）"
