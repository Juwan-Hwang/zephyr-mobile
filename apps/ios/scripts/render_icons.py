#!/usr/bin/env python3
"""把 design/prototype/brand/app-icon.svg 渲染成 App 图标（AppIcon.appiconset/AppIcon-1024.png）。

- iOS 会自己加圆角遮罩：图标必须是满版正方形、无透明通道。原型 SVG 的外形是超椭圆，
  这里把两条超椭圆外形路径替换成满版矩形（保留同一渐变与高光），标志路径原样保留。
- 依赖 cairosvg（pip install cairosvg）或 rsvg-convert（brew install librsvg）其一；Pillow 可选（去 alpha）。
"""
import os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
IOS = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(IOS))
SRC = os.path.join(REPO, "design", "prototype", "brand", "app-icon.svg")
OUT_DIR = os.path.join(IOS, "App", "Assets.xcassets", "AppIcon.appiconset")
OUT = os.path.join(OUT_DIR, "AppIcon-1024.png")
SIZE = 1024


def full_bleed(svg: str) -> str:
    # 外形路径以 "M256.0 128.0" 开头（超椭圆），把 d 换成满版方形。
    return re.sub(r'd="M256\.0 128\.0[^"]*"', 'd="M0 0 H256 V256 H0 Z"', svg)


def render(svg: str, out: str) -> None:
    try:
        import cairosvg  # type: ignore
        cairosvg.svg2png(bytestring=svg.encode(), write_to=out, output_width=SIZE, output_height=SIZE)
        return
    except ImportError:
        pass
    exe = shutil.which("rsvg-convert")
    if not exe:
        sys.exit("需要 cairosvg（pip install cairosvg）或 rsvg-convert（brew install librsvg）")
    with tempfile.NamedTemporaryFile("w", suffix=".svg", delete=False) as f:
        f.write(svg)
    subprocess.check_call([exe, "-w", str(SIZE), "-h", str(SIZE), "-o", out, f.name])
    os.unlink(f.name)


def strip_alpha(path: str) -> None:
    try:
        from PIL import Image  # type: ignore
    except ImportError:
        print("提示：未安装 Pillow，跳过去 alpha（满版不透明，通常无影响）", file=sys.stderr)
        return
    im = Image.open(path)
    if im.mode != "RGB":
        bg = Image.new("RGB", im.size, (11, 15, 25))
        bg.paste(im, mask=im.split()[-1] if im.mode in ("RGBA", "LA") else None)
        bg.save(path, optimize=True)


def main() -> None:
    svg = open(SRC, encoding="utf-8").read()
    patched = full_bleed(svg)
    if patched == svg:
        sys.exit("app-icon.svg 结构变了：没找到超椭圆外形路径，请更新 full_bleed()")
    os.makedirs(OUT_DIR, exist_ok=True)
    render(patched, OUT)
    strip_alpha(OUT)
    print(f"wrote {os.path.relpath(OUT, IOS)}")


if __name__ == "__main__":
    main()
