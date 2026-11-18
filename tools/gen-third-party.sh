#!/usr/bin/env bash
# 生成第三方许可清单：移动端安装包里实际链接的 Rust / Go 运行时依赖。
#   THIRD_PARTY_NOTICES.md   概要：许可口径 + 依赖表（名称、版本、许可）
#   THIRD_PARTY_LICENSES.txt 全文：按“许可文本相同”分组的各依赖许可文件原文（App 内“开源许可”页可直接展示）
#
# 范围：
#   Rust：core-mobile 的普通依赖闭包（不含 dev / build 依赖与 proc-macro 及其仅编译期子树），
#         按 iOS / Android 四个目标三元组过滤平台依赖后取并集；许可取 Cargo.toml 的 license 字段。
#   Go：  mihomo-mobile 在 android/{arm64,amd64}、ios/{arm64,amd64}（tags 同 build-mihomo.sh）下
#         `go list -deps` 实际编译进去的模块并集；许可按模块根目录 LICENSE/COPYING 文本识别。
# 需要：cargo、go（与 CI 同版本）、python3，并已 `git submodule update --init`。会联网下载依赖源码到本机缓存。
# 用法：tools/gen-third-party.sh [--check]   --check：与已提交文件比对，不一致退出 1
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CHECK=${1:-}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export TAGS; TAGS=$(sed -n 's/^TAGS="\(.*\)"$/\1/p' "$ROOT/tools/build-mihomo.sh")

RUST_TARGETS="aarch64-apple-ios aarch64-apple-ios-sim aarch64-linux-android x86_64-linux-android"
for t in $RUST_TARGETS; do
  (cd "$ROOT/core-mobile" && cargo metadata --format-version 1 --locked --filter-platform "$t" >"$TMP/rust-$t.json")
done
(cd "$ROOT/core-mobile" && cargo fetch --locked -q)

for t in android/arm64 android/amd64 ios/arm64 ios/amd64; do
  (cd "$ROOT/mihomo-mobile" && CGO_ENABLED=1 GOOS=${t%/*} GOARCH=${t#*/} go list -tags "$TAGS" -deps \
     -f '{{if not .Standard}}{{with .Module}}{{if .Replace}}{{.Replace.Path}}	{{.Replace.Version}}	{{.Replace.Dir}}{{else}}{{.Path}}	{{.Version}}	{{.Dir}}{{end}}{{end}}{{end}}' . ) >>"$TMP/go.tsv"
done
GOVERSION=$(go env GOVERSION)

python3 - "$ROOT" "$TMP" "$GOVERSION" "$RUST_TARGETS" <<'PY'
import glob, hashlib, json, os, re, sys
root, tmp, gover, rtargets = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].split()

LIC_GLOBS = ("LICENSE*", "LICENCE*", "COPYING*", "COPYRIGHT*", "NOTICE*", "UNLICENSE*")
def license_files(d):
    out = []
    for g in LIC_GLOBS:
        for p in glob.glob(os.path.join(d, g)) + glob.glob(os.path.join(d, g.lower())):
            if os.path.isfile(p) and p not in out:
                out.append(p)
    return sorted(out)

def classify(text):
    t = " ".join(text.split())
    if "GNU LESSER GENERAL PUBLIC LICENSE" in t:
        return "LGPL-3.0" if "Version 3" in t else "LGPL-2.1" if "Version 2.1" in t else "LGPL"
    if "GNU GENERAL PUBLIC LICENSE" in t:
        return "GPL-3.0" if "Version 3" in t else "GPL-2.0" if "Version 2" in t else "GPL"
    m = re.search(r"GNU General Public License as published by the Free Software Foundation, either version (\d)", t)
    if m: return f"GPL-{m.group(1)}.0-or-later"
    if "Mozilla Public License" in t and "2.0" in t: return "MPL-2.0"
    if "Apache License" in t and "Version 2.0" in t: return "Apache-2.0"
    if "Boost Software License" in t: return "BSL-1.0"
    if "free and unencumbered software released into the public domain" in t: return "Unlicense"
    if "CC0" in t or "Creative Commons Legal Code" in t: return "CC0-1.0"
    if "Permission is hereby granted, free of charge" in t: return "MIT"
    if re.search(r"Permission to use, copy, modify, and(/or)? distribute", t): return "ISC"
    if "Redistribution and use in source and binary forms" in t:
        return "BSD-3-Clause" if re.search(r"Neither the name|names of (its|the) contributors", t) else "BSD-2-Clause"
    if "UNICODE" in t.upper() and "DATA FILES AND SOFTWARE" in t.upper(): return "Unicode-3.0"
    if "zlib" in t.lower() and "altered source versions must be plainly marked" in t: return "Zlib"
    return None

# ---------- Rust ----------
rust = {}
for t in rtargets:
    m = json.load(open(f"{tmp}/rust-{t}.json"))
    pk = {p["id"]: p for p in m["packages"]}
    nodes = {n["id"]: n for n in m["resolve"]["nodes"]}
    rootid = m["resolve"]["root"]
    seen, st = set(), [rootid]
    while st:
        i = st.pop()
        if i in seen: continue
        seen.add(i)
        if any("proc-macro" in tg["kind"] for tg in pk[i]["targets"]):
            continue  # 编译期代码生成，不进二进制
        for d in nodes[i]["deps"]:
            if any(k["kind"] is None for k in d["dep_kinds"]):
                st.append(d["pkg"])
    for i in seen:
        p = pk[i]
        if i == rootid or any("proc-macro" in tg["kind"] for tg in p["targets"]): continue
        rust[(p["name"], p["version"])] = p
rust_rows = []
for (n, v), p in sorted(rust.items()):
    lic = p.get("license") or "（未声明，见许可文件）"
    src = "vendor/zephyr（子模块）" if p.get("source") is None else "crates.io"
    d = os.path.dirname(p["manifest_path"]); files = license_files(d)
    while not files and p.get("source") is None and d.startswith(root) and d != root:
        d = os.path.dirname(d); files = license_files(d)  # 子模块 crate：取仓库根的 LICENSE
    rust_rows.append((n, v, lic, src, files))

# ---------- Go ----------
# 模块包里没带许可文件、已人工核对仓库的（核对后写在这里，附依据）
GO_OVERRIDES = {
    "github.com/metacubex/chacha": "MIT（模块包未附许可文件；仓库 LICENSE 为 MIT，GitHub API 2026-11-18 核对）",
}
# 需要关注的许可（与安装包的 GPL-3.0 分发关系需留意）
GO_NOTES = {
    "github.com/rasky/go-lzo": "README 称沿用原 LZO 的 GPLv2（原 LZO 库为 GPL-2.0-or-later）；若为 GPL-2.0-only 则与 GPL-3.0 不兼容，由上游 mihomo 引入，需跟进",
}
go = {}
for line in open(f"{tmp}/go.tsv"):
    path, ver, d = (line.rstrip("\n").split("\t") + ["", ""])[:3]
    if not ver: continue  # 本模块 mihomo-mobile 自身
    go[(path, ver)] = d
go_rows = []
for (path, ver), d in sorted(go.items()):
    files = license_files(d) if d else []
    kinds = []
    for f in files:
        k = classify(open(f, errors="replace").read())
        if k and k not in kinds: kinds.append(k)
    lic = " AND ".join(kinds) if kinds else GO_OVERRIDES.get(path, "未识别（需人工确认）")
    go_rows.append((path, ver, lic, files))

# ---------- 写 NOTICES ----------
def count(rows, i):
    c = {}
    for r in rows: c[r[i]] = c.get(r[i], 0) + 1
    return sorted(c.items(), key=lambda x: (-x[1], x[0]))
def esc(s): return s.replace("|", "\\|")
mihomo_ver = next((v for (p, v) in go if p == "github.com/metacubex/mihomo"), "?")
L = []
L.append("# 第三方许可声明（Third-Party Notices）\n")
L.append("> 本文件由 `tools/gen-third-party.sh` 生成，请勿手改；依赖升级后重新生成（`--check` 校验是否最新）。")
L.append("> 各依赖的许可原文见 [THIRD_PARTY_LICENSES.txt](THIRD_PARTY_LICENSES.txt)。\n")
L.append("## 许可口径\n")
L.append("- **本仓库自有源码**：MIT（见 [LICENSE](LICENSE)）。")
L.append(f"- **移动端安装包**（iOS / Android）静态链接了 [mihomo](https://github.com/MetaCubeX/mihomo) `{mihomo_ver}`（GPL-3.0，见 [mihomo-mobile/LICENSE](mihomo-mobile/LICENSE)），"
         "因此**安装包整体按 GPL-3.0 分发**。每个发布版本的对应源码即本仓库对应的 tag（如 `mobile-v1.0`），"
         "其中 `vendor/zephyr` 子模块 commit、`core-mobile/Cargo.lock` 与 `mihomo-mobile/go.sum` 锁定了全部依赖版本。")
L.append("- 除下方 ⚠️ 标出的项外，下列依赖的许可均与 GPL-3.0 兼容（MIT / Apache-2.0 / BSD / ISC / Zlib / BSL-1.0 / Unicode-3.0 / MPL-2.0 / LGPL-3.0 / GPL-3.0(-or-later) 等）。")
L.append("- **MPL-2.0**（`uniffi*` 等）：文件级 copyleft。分发二进制时须告知其源码获取方式并附 MPL-2.0 全文："
         "源码见 crates.io 对应版本（https://crates.io/crates/<名称>/<版本>）及本仓库 tag；许可全文见 THIRD_PARTY_LICENSES.txt。"
         "本项目未修改任何 MPL-2.0 文件。")
L.append(f"- Go 标准库与运行时（{gover}）：BSD-3-Clause。")
for p, v, _, _ in go_rows:
    if p in GO_NOTES: L.append(f"- ⚠️ `{p}` {v}：{GO_NOTES[p]}。")
L.append("")
L.append(f"## Rust 运行时依赖（core-mobile，{len(rust_rows)} 个）\n")
L.append("目标：" + "、".join(f"`{t}`" for t in rtargets) + "；不含 dev / build 依赖与 proc-macro。\n")
L.append("许可分布：" + "，".join(f"{k} ×{v}" for k, v in count(rust_rows, 2)) + "\n")
L.append("| crate | 版本 | 许可（Cargo.toml） | 来源 |\n|---|---|---|---|")
for n, v, lic, src, _ in rust_rows: L.append(f"| {n} | {v} | {esc(lic)} | {src} |")
L.append(f"\n## Go 运行时依赖（mihomo-mobile，{len(go_rows)} 个模块）\n")
L.append(f"目标：android/arm64、android/amd64、ios/arm64、ios/amd64，build tags `{os.environ['TAGS']}`；许可按模块根目录的许可文件识别。\n")
L.append("许可分布：" + "，".join(f"{k} ×{v}" for k, v in count(go_rows, 2)) + "\n")
L.append("| 模块 | 版本 | 许可 |\n|---|---|---|")
for p, v, lic, _ in go_rows: L.append(f"| {p} | {v} | {esc(lic)} |")
open(f"{tmp}/THIRD_PARTY_NOTICES.md", "w").write("\n".join(L) + "\n")

# ---------- 写 LICENSES 全文（相同文本合并）----------
groups = {}
def add(label, files):
    for f in files:
        txt = open(f, errors="replace").read().replace("\r\n", "\n").strip() + "\n"
        h = hashlib.sha256(txt.encode()).hexdigest()
        g = groups.setdefault(h, {"text": txt, "who": []})
        if label not in g["who"]: g["who"].append(label)
for n, v, _, _, files in rust_rows: add(f"{n} {v} (Rust)", files)
for p, v, _, files in go_rows: add(f"{p} {v} (Go)", files)
missing = [f"{n} {v} (Rust)" for n, v, _, _, f in rust_rows if not f] + [f"{p} {v} (Go)" for p, v, _, f in go_rows if not f]
out = ["Zephyr Mobile — third-party license texts", "Generated by tools/gen-third-party.sh. Do not edit.", ""]
for g in sorted(groups.values(), key=lambda g: g["who"][0].lower()):
    out.append("=" * 78)
    out.append("Used by: " + ", ".join(g["who"]))
    out.append("-" * 78)
    out.append(g["text"])
if missing:
    out.append("=" * 78)
    out.append("No license file shipped in the package; license per its manifest / repository (standard texts below): " + ", ".join(missing))
    std = {}
    for rows, fi in ((rust_rows, 4), (go_rows, 3)):
        for r in rows:
            for f in r[fi]:
                k = classify(open(f, errors="replace").read())
                if k in ("MPL-2.0", "Apache-2.0") and k not in std and "Copyright" not in open(f, errors="replace").read()[:200]:
                    std[k] = open(f, errors="replace").read().replace("\r\n", "\n").strip() + "\n"
    for k in sorted(std):
        out.append("=" * 78)
        out.append(f"Standard license text: {k}")
        out.append("-" * 78)
        out.append(std[k])
open(f"{tmp}/THIRD_PARTY_LICENSES.txt", "w").write("\n".join(out) + "\n")
PY

status=0
for f in THIRD_PARTY_NOTICES.md THIRD_PARTY_LICENSES.txt; do
  if [[ "$CHECK" == "--check" ]]; then
    if ! cmp -s "$TMP/$f" "$ROOT/$f"; then echo "$f 不是最新：运行 tools/gen-third-party.sh" >&2; status=1; fi
  else
    cp "$TMP/$f" "$ROOT/$f"
  fi
done
exit $status
