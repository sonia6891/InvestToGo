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
import re
import shutil
import sys
from pathlib import Path

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
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    write_json(OUT / "Contents.json", {"info": INFO, "properties": {"provides-namespace": True}})
    count = 0
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
                shutil.copyfile(src, imageset / filename)
            write_json(imageset / "Contents.json", contents)
            count += 1
    print(f"exported {count} images into {OUT.relative_to(ROOT)}")
    if missing:
        print("missing sources:\n  " + "\n  ".join(missing), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
