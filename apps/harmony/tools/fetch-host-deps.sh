#!/bin/sh
# 宿主依赖（只在缺的时候装到 $HMOS_TOOLS_DIR，不需要 root）：
#   * Java ≥17：没有就从 Debian trixie 下 openjdk-21-jre-headless（宿主架构）解到 $HMOS_TOOLS_DIR/jdk
#   * 非 x86_64 宿主：qemu-user（宿主架构）→ $HMOS_TOOLS_DIR/qemu；amd64 运行库 → $HMOS_TOOLS_DIR/x86root
#     （SDK 的 restool / es2abc / syscap_tool 等是 x86_64；restool 会 dlopen 依赖 libGL 的 libimage_transcoder_shared.so）
# 需要 apt-get + dpkg-deb（Debian/Ubuntu 系）。用 Debian trixie 包源，与宿主发行版无关。
set -e
. "$(dirname "$0")/env.sh"
APTD=$HMOS_TOOLS_DIR/apt
mkdir -p "$APTD/state/lists/partial" "$APTD/cache/archives/partial" "$APTD/debs"
aptget() {  # aptget <arch> <args...>
  a=$1; shift
  echo "deb [arch=$a] http://deb.debian.org/debian trixie main
deb [arch=$a] http://deb.debian.org/debian-security trixie-security main" > "$APTD/sources-$a.list"
  apt-get -o Dir::Etc::SourceList="$APTD/sources-$a.list" -o Dir::Etc::SourceParts=/dev/null \
    -o Dir::State="$APTD/state-$a" -o Dir::Cache="$APTD/cache" -o APT::Architecture="$a" \
    -o APT::Architectures::="$a" -o Debug::NoLocking=1 -o Dir::State::status=/dev/null "$@"
}
fetch() {  # fetch <arch> <dest> <pkgs...>
  a=$1; d=$2; shift 2
  mkdir -p "$APTD/state-$a/lists/partial" "$d"
  [ -f "$APTD/state-$a/.updated" ] || { aptget "$a" update -q; touch "$APTD/state-$a/.updated"; }
  (cd "$APTD/debs" && aptget "$a" download "$@")
  for p in "$@"; do dpkg-deb -x "$(ls "$APTD"/debs/"${p}"_*_"$a".deb "$APTD"/debs/"${p}"_*_all.deb 2>/dev/null | head -1)" "$d"; done
}
HA=$(dpkg --print-architecture 2>/dev/null || echo arm64)

# Java
if [ -z "$JAVA" ] || ! "$JAVA" -version 2>&1 | grep -qE 'version "(1[7-9]|[2-9][0-9])'; then
  fetch "$HA" "$HMOS_TOOLS_DIR/jdk" openjdk-21-jre-headless
  # Debian 包的 conf/* 是指向 /etc/java-21-openjdk 的绝对软链 → 改指解出来的 etc
  C=$(ls -d "$HMOS_TOOLS_DIR"/jdk/usr/lib/jvm/java-21-openjdk-*/conf)
  find "$C" -type l | while read -r l; do t=$(readlink "$l"); case "$t" in /etc/*) ln -sfn "$HMOS_TOOLS_DIR/jdk$t" "$l";; esac; done
  echo "java: $(ls "$HMOS_TOOLS_DIR"/jdk/usr/lib/jvm/java-21-openjdk-*/bin/java)"
fi

[ "$HOST_ARCH" = x86_64 ] && { echo "x86_64 host: no qemu needed"; exit 0; }
if [ -z "$QEMU_X86" ]; then fetch "$HA" "$HMOS_TOOLS_DIR/qemu" qemu-user; fi
X86PKGS="libc6 libstdc++6 libgcc-s1 zlib1g libssl3t64 libatomic1 libgl1 libglvnd0 libglx0 libx11-6 libxcb1 libxau6 libxdmcp6 libbsd0 libmd0"
fetch amd64 "$X86ROOT" $X86PKGS
# merged-usr：qemu -L 需要 $X86ROOT/lib64/ld-linux-x86-64.so.2
[ -e "$X86ROOT/lib64" ] || ln -s usr/lib64 "$X86ROOT/lib64"
[ -e "$X86ROOT/lib" ] || ln -s usr/lib "$X86ROOT/lib"
echo "qemu: $( [ -n "$QEMU_X86" ] && echo "$QEMU_X86" || echo "$HMOS_TOOLS_DIR/qemu/usr/bin/qemu-x86_64")  x86root: $X86ROOT"
