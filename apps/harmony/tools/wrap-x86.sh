#!/bin/sh
# 非 x86_64 宿主：把给定目录里的 x86_64 可执行文件（不含 .so）就地改名 <name>.x86，
# 原位放一个 sh 包装 → qemu-x86_64 -L $X86ROOT 跑。幂等；x86_64 宿主上什么也不做。
# 用法：wrap-x86.sh <dir>...      （build-*.sh 会自动调用）
set -e
. "$(dirname "$0")/env.sh"
[ "$HOST_ARCH" = x86_64 ] && exit 0
[ -x "$QEMU_X86" ] || { echo "qemu-x86_64 not found: run tools/fetch-host-deps.sh or set QEMU_X86" >&2; exit 1; }
[ -d "$X86ROOT/lib64" ] || { echo "x86_64 sysroot missing at $X86ROOT: run tools/fetch-host-deps.sh" >&2; exit 1; }
# 包装脚本内容（每次都重写，便于升级）。HMOS_X86_LD_PATH：额外的 x86 .so 目录（冒号分隔），
# 例如 restool 会 dlopen hms/toolchains/lib/libimage_transcoder_shared.so，它依赖同目录 liblz4_shared.so。
write_wrapper() {
  cat > "$1" <<W
#!/bin/sh
d=\$(dirname "\$(readlink -f "\$0")")
exec "$QEMU_X86" -L "$X86ROOT" -E LD_LIBRARY_PATH="\$d:\$d/lib:\$d/../lib\${HMOS_X86_LD_PATH:+:\$HMOS_X86_LD_PATH}" "\$d/$(basename "$1").x86" "\$@"
W
  chmod +x "$1"
}
n=0
for dir in "$@"; do
  [ -d "$dir" ] || continue
  for x in $(find "$dir" -type f -name '*.x86' 2>/dev/null); do write_wrapper "${x%.x86}"; done
  for f in $(find "$dir" -type f -size +10k ! -name '*.js' ! -name '*.ts' ! -name '*.json' ! -name '*.x86' ! -name '*.so' ! -name '*.so.*' ! -name '*.jar' 2>/dev/null); do
    case "$(file -b "$f")" in
      *shared\ object*) ;;
      *x86-64*) mv "$f" "$f.x86"; write_wrapper "$f"; n=$((n+1));;
    esac
  done
done
echo "wrap-x86: wrapped $n new binaries"
