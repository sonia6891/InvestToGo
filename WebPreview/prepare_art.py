"""Turn the Figma AI illustrations (white background) into transparent, trimmed PNGs.

Usage, from the repository root:
    python -I WebPreview/prepare_art.py <folder-of-generated-pngs> <output-folder> [size]

Each image's white background is flood-filled from the edges (enclosed white areas such as a
clock face are kept), the edge is softened, the art is trimmed and fitted into a square canvas.
"""
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

SENTINEL = (255, 0, 255)
# Images whose generated background carries a soft floor shadow or glow need a looser cut.
THRESH = {"cat-saving.png": 46, "div-confirm.png": 52, "misc-bulb.png": 70}


def transparent(img, thresh=24):
    rgb = img.convert("RGB")
    w, h = rgb.size
    seeds = [(x, y) for x in range(0, w, 16) for y in (0, h - 1)] + [(x, y) for y in range(0, h, 16) for x in (0, w - 1)]
    for xy in seeds:
        if rgb.getpixel(xy) != SENTINEL and sum(rgb.getpixel(xy)) > 3 * 225:
            ImageDraw.floodfill(rgb, xy, SENTINEL, thresh=thresh)
    key = Image.new("RGB", (w, h), SENTINEL)
    diff = ImageChops.difference(rgb, key).convert("L")
    mask = diff.point(lambda v: 255 if v > 8 else 0).filter(ImageFilter.GaussianBlur(1.6))
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def fit(img, size, margin=0.04):
    box = img.getbbox() or (0, 0, img.width, img.height)
    art = img.crop(box)
    inner = int(size * (1 - 2 * margin))
    art.thumbnail((inner, inner), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(art, ((size - art.width) // 2, (size - art.height) // 2))
    return canvas


def main():
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    size = int(sys.argv[3]) if len(sys.argv) > 3 else 384
    dst.mkdir(parents=True, exist_ok=True)
    for p in sorted(src.glob("*.png")):
        fit(transparent(Image.open(p), THRESH.get(p.name, 24)), size).save(dst / p.name, optimize=True)
        print(p.name)


if __name__ == "__main__":
    main()
