#!/usr/bin/env python3
"""Lay the CI skin-matrix screenshots out like the design canvas: one row per skin, one column per screen.

Usage: python Scripts/contact_sheet.py <dir> <out.png>

<dir> holds the `<skin>-<screen>.png` files from the `skin-matrix` job (artifact ETFToGo-skin-matrix). A missing
shot is drawn as an empty, labelled frame so a failed launch is visible on the sheet, and the script exits 1.
Needs Pillow.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

# Rows, top to bottom, in the global-constraints order: (file id, name, skin number).
SKINS = [
    ("blackgold", "黑金", "SKN 001"),
    ("voxel", "像素", "SKN 002"),
    ("stitch", "縫線", "SKN 003"),
    ("sketch", "手繪", "SKN 004"),
]
# Columns, left to right, in the order of the brief (Task 13): (file id, label).
SCREENS = [
    ("splash", "開機"),
    ("onboarding1", "引導 1"),
    ("lobby", "大廳"),
    ("find", "找 ETF"),
    ("detail", "詳情"),
    ("dex", "圖鑑卡"),
    ("pocket", "口袋"),
    ("dividends", "配息"),
    ("tools", "工具"),
    ("skins", "換膚"),
    ("achievements", "成就"),
]

THUMB_W = 300  # each phone screenshot is scaled to this width
GAP = 24
ROW_LABEL_W = 200
HEADER_H = 56
BG = (236, 236, 232)
INK = (24, 24, 24)
MISSING = (200, 60, 60)

# Fonts with CJK glyphs: the repo's own subset font first (it covers every label above), then common system fonts.
FONT_CANDIDATES = [
    Path(__file__).resolve().parent.parent / "App" / "Resources" / "Fonts" / "NotoSansTC-Medium.ttf",
    Path("C:/Windows/Fonts/msjh.ttc"),
    Path("/System/Library/Fonts/PingFang.ttc"),
    Path("/System/Library/Fonts/STHeiti Medium.ttc"),
    Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"),
]


def load_font(size: int) -> ImageFont.ImageFont:
    for path in FONT_CANDIDATES:
        if path.exists():
            try:
                return ImageFont.truetype(str(path), size)
            except OSError:
                continue
    return ImageFont.load_default()


def thumb_height(folder: Path) -> int:
    """The scaled height of the first screenshot found (all come from one simulator), or a 19.5:9 phone."""
    for skin, _, _ in SKINS:
        for screen, _ in SCREENS:
            path = folder / f"{skin}-{screen}.png"
            if path.exists():
                with Image.open(path) as image:
                    return round(image.height * THUMB_W / image.width)
    return round(THUMB_W * 19.5 / 9)


def build(folder: Path, out: Path) -> tuple[int, list[str]]:
    th = thumb_height(folder)
    width = ROW_LABEL_W + len(SCREENS) * (THUMB_W + GAP) + GAP
    height = HEADER_H + len(SKINS) * (th + GAP) + GAP
    sheet = Image.new("RGB", (width, height), BG)
    draw = ImageDraw.Draw(sheet)
    head, label, small = load_font(30), load_font(28), load_font(18)

    for c, (screen, name) in enumerate(SCREENS):
        x = ROW_LABEL_W + c * (THUMB_W + GAP)
        draw.text((x + THUMB_W / 2, HEADER_H / 2), name, font=head, fill=INK, anchor="mm")

    missing: list[str] = []
    found = 0
    for r, (skin, skin_name, number) in enumerate(SKINS):
        y = HEADER_H + r * (th + GAP)
        draw.text((GAP, y + th / 2 - 20), skin_name, font=label, fill=INK, anchor="lm")
        draw.text((GAP, y + th / 2 + 16), number, font=small, fill=INK, anchor="lm")
        draw.text((GAP, y + th / 2 + 40), skin, font=small, fill=INK, anchor="lm")
        for c, (screen, _) in enumerate(SCREENS):
            x = ROW_LABEL_W + c * (THUMB_W + GAP)
            path = folder / f"{skin}-{screen}.png"
            if path.exists():
                with Image.open(path) as image:
                    sheet.paste(image.convert("RGB").resize((THUMB_W, th), Image.LANCZOS), (x, y))
                found += 1
            else:
                missing.append(path.name)
                draw.rectangle((x, y, x + THUMB_W, y + th), outline=MISSING, width=4)
                draw.text((x + THUMB_W / 2, y + th / 2), f"缺 {path.name}", font=small, fill=MISSING, anchor="mm")
            draw.rectangle((x, y, x + THUMB_W - 1, y + th - 1), outline=(150, 150, 150), width=1)

    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out, optimize=True)
    return found, missing


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    folder, out = Path(argv[1]), Path(argv[2])
    if not folder.is_dir():
        print(f"not a folder: {folder}", file=sys.stderr)
        return 2
    found, missing = build(folder, out)
    print(f"{out}: {found} of {len(SKINS) * len(SCREENS)} screenshots")
    for name in missing:
        print(f"missing {name}", file=sys.stderr)
    # The sheet is still written, with red frames; a missing shot is an error for CI.
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
