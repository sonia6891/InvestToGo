#!/usr/bin/env python3
"""Subset the bundled CJK skin fonts (ruling R13) and check that the app's own text is covered.

    python Scripts/subset_fonts.py            # rebuild App/Resources/Fonts/<font> from the full originals
    python Scripts/subset_fonts.py --check    # verify the bundled fonts cover every character the app ships

The full fonts are not kept in the working tree. They are read from git history (commit FULL_FONTS_COMMIT, where
they were added from google/fonts and the LXGW WenKai TC release), or from `--source <dir>` if you have the files.
The subsets replace the bundled files in place, with the same file names, family names and PostScript names, so
`Font.custom` lookups and UIAppFonts in project.yml are unchanged. Nothing is renamed, so the OFL Reserved Font Name
clause (Noto Sans TC reserves "Source") is not touched.

Character set kept (each font keeps only the glyphs it has of these):
  * ASCII, Latin-1, general punctuation, letterlike, number forms, arrows, math operators, enclosed alphanumerics,
    geometric shapes (▲▼), misc symbols and dingbats, CJK symbols and punctuation, Bopomofo, fullwidth forms;
  * Big5 level 1 (0xA440-0xC67E, 5,401 characters), the encoding's frequently-used set, built from the Ministry of
    Education's 常用國字標準字體表 (4,808) plus common extras; read from Python's own big5 codec, so no download;
  * the Big5 symbol rows (0xA140-0xA3BF);
  * every non-ASCII character in the app's sources and data: App/**, PocketCore/** (Swift, skins.json, the bundled
    catalogue with every ETF name, dividends, fees, market data), project.yml and Scripts/contact_sheet.py.

Needs fontTools (pyftsubset). `--check` needs only fontTools and the repo.
"""
from __future__ import annotations

import argparse
import io
import subprocess
import sys
import unicodedata
from pathlib import Path

from fontTools.subset import Options, Subsetter, load_font, save_font
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "App" / "Resources" / "Fonts"
# The commit that added the full fonts; `git show` reads them back from history.
FULL_FONTS_COMMIT = "a5573d2"

# Fonts that are subset. DotGothic16 is a Japanese font: it keeps what it has of the same set, and the app's Chinese
# characters it never had fall back to the system font exactly as before (CHECK_EXEMPT).
SUBSET = [
    "NotoSansTC-Bold.ttf",
    "NotoSansTC-Medium.ttf",
    "NotoSerifTC-Bold.otf",
    "NotoSerifTC-Medium.otf",
    "LXGWWenKaiTC-Medium.ttf",
    "DotGothic16-Regular.ttf",
]
CHECK_EXEMPT = {"DotGothic16-Regular.ttf"}

RANGES = [
    (0x0020, 0x007E),  # ASCII
    (0x00A0, 0x00FF),  # Latin-1 supplement (×, ·, °)
    (0x2000, 0x206F),  # general punctuation (…, —, ‧)
    (0x20A0, 0x20CF),  # currency
    (0x2100, 0x218F),  # letterlike, number forms (℃, Ⅰ)
    (0x2190, 0x21FF),  # arrows (→ ←)
    (0x2200, 0x22FF),  # math operators (−, ≈)
    (0x2460, 0x24FF),  # enclosed alphanumerics (①)
    (0x2500, 0x257F),  # box drawing
    (0x25A0, 0x25FF),  # geometric shapes (▲ ▼ ●)
    (0x2600, 0x27BF),  # misc symbols, dingbats (★ ✓)
    (0x3000, 0x303F),  # CJK symbols and punctuation (「」『』、。)
    (0x3100, 0x312F),  # Bopomofo
    (0xFE30, 0xFE4F),  # CJK compatibility forms
    (0xFF01, 0xFF65),  # fullwidth forms (－ ＋ ：), halfwidth punctuation
    (0xFFE0, 0xFFE6),  # fullwidth signs (￥)
]

SCAN_ROOTS = ["App", "PocketCore"]
SCAN_FILES = ["project.yml", "Scripts/contact_sheet.py"]
SCAN_SUFFIXES = {".swift", ".json", ".strings", ".stringsdict", ".xcstrings", ".plist", ".yml", ".txt", ".py"}


def is_cjk(ch: str) -> bool:
    cp = ord(ch)
    return 0x3400 <= cp <= 0x9FFF or 0xF900 <= cp <= 0xFAFF or 0x20000 <= cp <= 0x3FFFF


def app_characters() -> set[str]:
    """Every non-ASCII, printable character in the app's sources and bundled data (not the font licences)."""
    files: list[Path] = [ROOT / f for f in SCAN_FILES]
    for top in SCAN_ROOTS:
        files += [p for p in (ROOT / top).rglob("*") if p.is_file() and p.suffix in SCAN_SUFFIXES and "Fonts" not in p.parts]
    chars: set[str] = set()
    for path in files:
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        chars.update(ch for ch in text if ord(ch) > 0x7E and ch.isprintable())
    return chars


def big5_rows(lead: range) -> set[str]:
    chars = set()
    for hi in lead:
        for lo in list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF)):
            try:
                chars.add(bytes([hi, lo]).decode("big5"))
            except UnicodeDecodeError:
                pass
    return chars


def common_traditional() -> set[str]:
    """Big5 level 1: 0xA440 to 0xC67E."""
    return {c for c in big5_rows(range(0xA4, 0xC7)) if is_cjk(c) and c.encode("big5") <= b"\xc6\x7e"}


def charset() -> set[str]:
    chars = {chr(cp) for lo, hi in RANGES for cp in range(lo, hi + 1)}
    chars |= big5_rows(range(0xA1, 0xA4))  # Big5 symbols
    chars |= common_traditional()
    chars |= app_characters()
    return chars


def original(name: str, source: Path | None) -> bytes:
    if source:
        return (source / name).read_bytes()
    return subprocess.run(["git", "show", f"{FULL_FONTS_COMMIT}:App/Resources/Fonts/{name}"], cwd=ROOT, check=True,
                          capture_output=True).stdout


def names(font: TTFont) -> list[tuple[int, int, int, int, str]]:
    """The standard name records (IDs below 256: family, style, full name, PostScript name, version, licence ...).
    Font-specific IDs (256+) name axes and features; the subsetter drops the ones nothing references any more."""
    return sorted((r.nameID, r.platformID, r.platEncID, r.langID, r.toUnicode()) for r in font["name"].names if r.nameID < 256)


def subset(source: Path | None) -> int:
    chars = charset()
    unicodes = sorted({ord(c) for c in chars})
    print(f"character set: {len(unicodes)} code points ({len(common_traditional())} Big5 level 1, "
          f"{len({c for c in app_characters() if is_cjk(c)})} CJK in the app)")
    total_before = total_after = 0
    for name in SUBSET:
        data = original(name, source)
        options = Options()
        options.name_IDs = ["*"]           # keep every name record: family, PostScript, licence, version
        options.name_languages = ["*"]
        options.name_legacy = True
        options.layout_features = ["*"]    # keep all OpenType features (palt, vert, kern ...)
        options.notdef_outline = True
        options.glyph_names = False
        options.hinting = False             # iOS renders CJK unhinted
        options.drop_tables += ["DSIG"]
        font = load_font(io.BytesIO(data), options)
        before_names = names(font)
        subsetter = Subsetter(options)
        subsetter.populate(unicodes=unicodes)
        subsetter.subset(font)
        out = FONTS / name
        save_font(font, str(out), options)
        after = TTFont(str(out))
        if names(after) != before_names:
            raise SystemExit(f"{name}: name table changed")
        kept = len(after.getBestCmap())
        total_before += len(data)
        total_after += out.stat().st_size
        print(f"{name}: {len(data) / 1e6:.2f} MB -> {out.stat().st_size / 1e6:.2f} MB, {kept} characters, "
              f"family {after['name'].getDebugName(1)!r}, PostScript {after['name'].getDebugName(6)!r}")
    print(f"total: {total_before / 1e6:.2f} MB -> {total_after / 1e6:.2f} MB")
    return 0


def check() -> int:
    """Every CJK character and symbol the app ships is in each Traditional Chinese font's cmap."""
    # CJK compatibility ideographs (U+F900-FAFF, e.g. 金 U+F90A in official fund names) are checked as their NFC
    # unified form: the full fonts never had most of them, so they fell back to the system font before subsetting too.
    wanted = {unicodedata.normalize("NFC", c) for c in app_characters()
              if is_cjk(c) or 0x3000 <= ord(c) <= 0x303F or 0xFF01 <= ord(c) <= 0xFF5E}
    wanted |= set("▲▼－×・→←…「」『』")
    failed = False
    for name in SUBSET:
        if name in CHECK_EXEMPT:
            continue
        cmap = TTFont(str(FONTS / name)).getBestCmap()
        missing = sorted(c for c in wanted if ord(c) not in cmap)
        if missing:
            failed = True
            print(f"FAIL {name}: {len(missing)} characters missing: {''.join(missing[:200])}")
        else:
            print(f"ok   {name}: all {len(wanted)} app characters present")
    skins = (ROOT / "PocketCore/Sources/PocketCore/Resources/skins.json").read_text(encoding="utf-8")
    skin_chars = {unicodedata.normalize("NFC", c) for c in skins if is_cjk(c)}
    for name in SUBSET:
        if name in CHECK_EXEMPT:
            continue
        cmap = TTFont(str(FONTS / name)).getBestCmap()
        if any(ord(c) not in cmap for c in skin_chars):
            failed = True
            print(f"FAIL {name}: a skins.json character is missing")
    if failed:
        print("Re-run `python Scripts/subset_fonts.py` so the new characters are kept.")
        return 1
    return 0


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="verify coverage of the bundled fonts; change nothing")
    parser.add_argument("--source", type=Path, help="folder with the full fonts (default: git history)")
    args = parser.parse_args()
    return check() if args.check else subset(args.source)


if __name__ == "__main__":
    sys.exit(main())
