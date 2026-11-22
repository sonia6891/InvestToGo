#!/usr/bin/env python3
"""Copy every skin's art into App/Assets.xcassets/Skins/<skinID>/<name>.imageset.

Screens ask for art by name only: Image("\\(skin.art.folder)/\\(name)"), e.g. "Skins/stitch/find".
Both the Skins folder and each skin folder provide a namespace, so the folder is part of the name.

Sources:
  blackgold  design/3d/*.png (transparent "cut" renders)
  voxel      design/3d/skins/voxel/*.png
  stitch     design/3d/skins/stitch/*.svg         (node stitch.mjs <dir>)
  sketch     design/3d/skins/sketch_doodle/*.svg  (node draw.mjs <dir>)
  badge      design/3d/skins/badges/<skin>.svg    (node badges.mjs <dir>)

PNGs go in the universal slot at their rendered size (no @2x/@3x re-render yet). SVGs keep their vector data.
Run from anywhere: python Scripts/export_skin_art.py
"""
import json
import math
import os
import re
import shutil
import stat
import sys
from pathlib import Path

from PIL import Image, ImageChops

ROOT = Path(__file__).resolve().parent.parent
D3 = ROOT / "design" / "3d"
SK = D3 / "skins"
OUT = ROOT / "App" / "Assets.xcassets" / "Skins"
INFO = {"author": "xcode", "version": 1}

# SkinArtName (PocketCore/Sources/PocketCore/Design/Skins.swift) → source file stem, per skin.
ICONS = {"find": "icon_magnifier", "dividends": "icon_stack", "tools": "icon_calc", "calc": "icon_calc",
         "fees": "icon_bars", "reminder": "icon_bell", "achievements": "icon_target", "goal": "icon_target",
         "crown": "icon_crown"}


def mapping(skin):
    if skin == "blackgold":
        m = {"hero_dollar": D3 / "blocks_dollar_cut.png", "pocket": D3 / "blocks_pocket_cut.png",
             "pocket_icon": D3 / "blocks_pocket_icon.png"}
        m.update({k: D3 / f"{v}.png" for k, v in ICONS.items()})
        m["badge"] = SK / "badges" / "blackgold.svg"
        return m
    if skin == "voxel":
        src = SK / "voxel"
        m = {"hero_dollar": src / "dollar.png", "pocket": src / "pocket_icon.png", "pocket_icon": src / "pocket_icon.png"}
        m.update({k: src / f"{v}.png" for k, v in ICONS.items()})
        m["badge"] = SK / "badges" / "pixel.svg"
        return m
    src = SK / ("stitch" if skin == "stitch" else "sketch_doodle")
    m = {"hero_dollar": src / "dollar.svg", "pocket": src / "pocket_icon.svg", "pocket_icon": src / "pocket_icon.svg"}
    m.update({k: src / f"{v}.svg" for k, v in ICONS.items()})
    m["badge"] = SK / "badges" / f"{skin}.svg"
    extra = [f"digit_{n}" for n in range(10)]
    if skin == "stitch":
        extra += [f"digit_{n}_b" for n in range(10)] + ["patch"]
    else:
        extra += [f"tally_{n}" for n in range(1, 6)]
    m.update({name: src / f"{name}.svg" for name in extra})
    return m


SKINS = ["blackgold", "voxel", "stitch", "sketch"]

# The two 3D skins ship raster art. Each PNG is written losslessly first (fully transparent pixels carry no colour);
# one that is still over BUDGET_BYTES keeps its full alpha but has its colour rounded to 6 bits per channel, which is
# at most 2 levels of error. Palette quantizing (256 colours) was tried and rejected: it stepped the soft edges.
# Quality is the PSNR of the image as the skin shows it, composited on its page colour, over the object's pixels
# (alpha > 0) and over its semi-transparent edge pixels (0 < alpha < 255); whole-image PSNR is flattered by the flat
# page colour around the object.
BUDGET_BYTES = 150_000
COLOR_BITS = 6
PSNR_FLOOR = 36.0       # object pixels
EDGE_FLOOR = 33.0       # semi-transparent edge pixels
TOTAL_LIMIT = 4_000_000
PAGE_COLOR = {"blackgold": (0x1A, 0x1A, 0x1D), "voxel": (0x1B, 0x1F, 0x4B)}  # colors.page in skins.json


def budget(src):
    return BUDGET_BYTES


def on_page(image, page):
    base = Image.new("RGBA", image.size, page + (255,))
    return Image.alpha_composite(base, image.convert("RGBA")).convert("RGB")


def psnr(a, b, mask):
    """PSNR in dB of two RGB images over the pixels `mask` selects; infinity when they match, None when it is empty."""
    pixels = mask.histogram()[255]
    if pixels == 0:
        return None
    hist = ImageChops.difference(a, b).histogram(mask)
    squares = sum(count * (i % 256) ** 2 for i, count in enumerate(hist))
    if squares == 0:
        return math.inf
    return 10 * math.log10(255 ** 2 / (squares / (pixels * 3)))


def scores(original, written, page):
    """(object PSNR, edge PSNR) of `written` against `original`; None for an image with no edge pixels."""
    alpha = original.convert("RGBA").getchannel("A")
    solid = alpha.point(lambda v: 255 if v else 0)
    edge = alpha.point(lambda v: 255 if 0 < v < 255 else 0)
    a, b = on_page(original, page), on_page(written, page)
    return psnr(a, b, solid), psnr(a, b, edge)


def reduced(image, bits):
    """`image` with fully transparent pixels cleared and, when bits < 8, colour rounded to `bits` bits per channel."""
    r, g, b, a = image.convert("RGBA").split()
    step = 1 << (8 - bits)
    bands = [band.point(lambda v: min(255, (v + step // 2) // step * step)) if bits < 8 else band for band in (r, g, b)]
    clear = Image.new("L", image.size, 0)
    seen = a.point(lambda v: 255 if v else 0)
    return Image.merge("RGBA", [Image.composite(band, clear, seen) for band in bands] + [a])


def optimize_png(src, dst, page):
    """Write `src` to `dst` as a PNG and return (bytes written, object PSNR, edge PSNR) against the original on `page`.

    Lossless when that fits budget(src); otherwise colour is rounded to COLOR_BITS bits per channel.
    """
    original = Image.open(src)
    original.load()
    reduced(original, 8).save(dst, optimize=True)
    if dst.stat().st_size > budget(src):
        reduced(original, COLOR_BITS).save(dst, optimize=True)
    with Image.open(dst) as written:
        solid, edge = scores(original, written, page)
    return dst.stat().st_size, solid, edge


def _clear_readonly(func, path, _exc):
    """Windows keeps a read-only flag on some folders git checked out; clear it and retry the removal."""
    os.chmod(path, stat.S_IWRITE)
    func(path)

RGBA = re.compile(r'(fill|stroke)="rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)"')


def asset_svg(text):
    """Asset catalogs render SVG with CoreSVG, which wants plain colours: rgba() becomes colour + opacity."""
    def sub(m):
        attr, r, g, b, a = m.groups()
        return f'{attr}="#{int(r):02X}{int(g):02X}{int(b):02X}" {attr}-opacity="{float(a):g}"'
    return RGBA.sub(sub, text)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def main():
    missing = []
    if OUT.exists():
        shutil.rmtree(OUT, onexc=_clear_readonly)
    OUT.mkdir(parents=True)
    write_json(OUT / "Contents.json", {"info": INFO, "properties": {"provides-namespace": True}})
    count = 0
    png_total = 0
    results = []
    for skin in SKINS:
        folder = OUT / skin
        folder.mkdir()
        write_json(folder / "Contents.json", {"info": INFO, "properties": {"provides-namespace": True}})
        for name, src in mapping(skin).items():
            if not src.exists():
                missing.append(f"{skin}/{name} ← {src.relative_to(ROOT)}")
                continue
            imageset = folder / f"{name}.imageset"
            imageset.mkdir()
            filename = f"{name}{src.suffix}"
            contents = {"images": [{"filename": filename, "idiom": "universal"}], "info": INFO}
            if src.suffix == ".svg":
                (imageset / filename).write_text(asset_svg(src.read_text(encoding="utf-8")), encoding="utf-8")
                contents["properties"] = {"preserves-vector-representation": True}
            else:
                size, solid, edge = optimize_png(src, imageset / filename, PAGE_COLOR[skin])
                png_total += size
                results.append((f"{skin}/{name}", size, solid, edge))
            write_json(imageset / "Contents.json", contents)
            count += 1
    print(f"exported {count} images into {OUT.relative_to(ROOT)}")
    failed = False
    for label, size, solid, edge in sorted(results, key=lambda r: r[2]):
        low = solid < PSNR_FLOOR or (edge is not None and edge < EDGE_FLOOR)
        failed = failed or low
        shown = "  none" if edge is None else f"{edge:6.2f}"
        print(f"  {label:<24} {size:>9,} bytes  object {solid:6.2f} dB  edge {shown} dB" + ("  <-- below floor" if low else ""))
    worst = min((r[2] for r in results), default=math.inf)
    worst_edge = min((r[3] for r in results if r[3] is not None), default=math.inf)
    print(f"PNG total {png_total:,} bytes (limit {TOTAL_LIMIT:,}); worst object PSNR {worst:.2f} dB (floor {PSNR_FLOOR}), "
          f"worst edge PSNR {worst_edge:.2f} dB (floor {EDGE_FLOOR})")
    if png_total > TOTAL_LIMIT:
        print("PNG total is over the limit", file=sys.stderr)
        failed = True
    if missing:
        print("missing sources:\n  " + "\n  ".join(missing), file=sys.stderr)
        failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
