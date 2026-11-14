#!/usr/bin/env python3
"""Housekeeping for the screenshots native-ui.yml takes in the simulator.

    python Scripts/screens.py check <picture.png>...
        Exit 1 when a picture is missing or is a blank frame: one flat colour below the status bar, which is the
        launch screen or a page that had not drawn yet. Each such picture gets a GitHub `::error::` line. Needs Pillow.

    python Scripts/screens.py collect <attachments-dir> <out-dir>
        Copy the `store-*` attachments of a UI test run (as `xcresulttool export attachments` writes them, with its
        manifest.json) into <out-dir> under their own names, leaving alone any picture that is already there.
"""
from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path


def blank(path: Path) -> bool:
    """One flat colour below the status bar (the top eighth is left out: the clock and battery are always there)."""
    from PIL import Image, ImageStat

    image = Image.open(path).convert("L")
    width, height = image.size
    return ImageStat.Stat(image.crop((0, height // 8, width, height))).stddev[0] < 3


def check(pictures: list[str]) -> int:
    bad = 0
    for name in pictures:
        path = Path(name)
        if not path.is_file():
            print(f"::error::{name} is missing")
            bad += 1
        elif blank(path):
            print(f"::error::{name} is a blank frame")
            bad += 1
        else:
            print(f"ok {name}")
    return 1 if bad else 0


def collect(attachments: Path, out: Path) -> int:
    manifest = attachments / "manifest.json"
    if not manifest.is_file():
        print(f"no manifest in {attachments}")
        return 0
    out.mkdir(parents=True, exist_ok=True)
    for test in json.loads(manifest.read_text(encoding="utf-8")):
        for item in test.get("attachments", []):
            exported = item.get("exportedFileName", "")
            # "store-backtest_0_<uuid>.png": the name the test gave, then what Xcode adds to it.
            given = item.get("suggestedHumanReadableName", "").split("_")[0]
            source = attachments / exported
            if not given.startswith("store-") or not exported or not source.is_file():
                continue
            target = out / f"{given}.png"
            if target.exists():
                continue
            shutil.copyfile(source, target)
            print(f"collected {target}")
    return 0


def main(arguments: list[str]) -> int:
    if len(arguments) >= 2 and arguments[0] == "check":
        return check(arguments[1:])
    if len(arguments) == 3 and arguments[0] == "collect":
        return collect(Path(arguments[1]), Path(arguments[2]))
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
