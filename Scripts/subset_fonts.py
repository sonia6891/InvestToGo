#!/usr/bin/env python3
"""Subset the bundled CJK skin fonts (ruling R13) and check that the app's own text is covered.

    python Scripts/subset_fonts.py            # rebuild App/Resources/Fonts/<font> from the full originals
    python Scripts/subset_fonts.py --check    # verify the bundled fonts cover every character the app ships

The full fonts are not kept in the working tree. They are read from git history (commit FULL_FONTS_COMMIT, where
they were added from google/fonts and the LXGW WenKai TC release), or from `--source <dir>` if you have the files.
The subsets replace the bundled files in place, with the same file names, family names and PostScript names, so
`Font.custom` lookups and UIAppFonts in project.yml are unchanged. Nothing is renamed, so the OFL Reserved Font Name
(RFN) clause matters for every font that is subset, because a subset is a Modified Version and may not keep an RFN:
  * Noto Sans TC reserves "Source" only, a name these fonts do not carry, so subsetting them is fine.
  * Bree Serif reserves "Bree" and "Bree Serif", and Press Start 2P reserves "Press Start 2P". Both names are the
    fonts' own family names, which code references and cannot be renamed. So these two are shipped UNMODIFIED, the
    original files from a5573d2, and are not subset (not in ORIGINALS, SUBSET or LATIN below).
The other fonts (Anton, Caveat, JetBrains Mono, DotGothic16, LXGW WenKai TC, Noto Serif TC) are subset in place.

Character set kept (each font keeps only the glyphs it has of these):
  * ASCII, Latin-1, general punctuation, letterlike, number forms, arrows, math operators, enclosed alphanumerics,
    geometric shapes (▲▼), misc symbols and dingbats, CJK symbols and punctuation, Bopomofo, fullwidth forms, and the
    Big5 symbol rows (0xA140-0xA3BF);
  * every non-ASCII character in the app's sources and data: App/**, PocketCore/** (Swift, skins.json, the bundled
    catalogue with every ETF name, dividends, fees, market data), project.yml and Scripts/contact_sheet.py;
  * every CJK character of the bundled catalogue and WebPreview/etf-data.json (NFC);
  * an insurance list: the first INSURANCE characters of Scripts/common-chars.txt (most frequent first), for fund
    names that arrive at runtime. INSURANCE is the largest multiple of 50 that keeps the 4,000,000 byte size gate green
    with at least 50 KB to spare, counting the two unmodified fonts.

Needs fontTools (pyftsubset). `--check` needs only fontTools and the repo.
"""
from __future__ import annotations

import argparse
import hashlib
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
TOTAL_LIMIT = 4_000_000
# How many characters of Scripts/common-chars.txt are kept on top of the app's own text.
INSURANCE = 550

# The full fonts the subsets are made from: where they came from (ruling R7), their version string (name ID 5) and the
# sha256 of the file in FULL_FONTS_COMMIT. Task 2 did not record the exact download URL of each file, so `source` is
# the upstream project; the version and hash identify the file. A source file with another hash is refused. `commit`
# is where the full file was added to git (default FULL_FONTS_COMMIT).
ORIGINALS = {
    "NotoSansTC-Bold.ttf": {
        "source": "https://github.com/google/fonts/tree/main/ofl/notosanstc (static instance)",
        "version": "Version 2.04;241114210131;non-release",
        "sha256": "f946ba1299d235d160ea03fa781dc6cc96809701c6d000cc62a7523f077197d9"},
    "NotoSansTC-Medium.ttf": {
        "source": "https://github.com/google/fonts/tree/main/ofl/notosanstc (static instance)",
        "version": "Version 2.04;241114210131;non-release",
        "sha256": "c00f82dc830efbe3e0571fc26053186e047b4d9c5d9023a3bd6f63c6ffd81aea"},
    "NotoSerifTC-Bold.otf": {
        "source": "https://github.com/google/fonts/tree/main/ofl/notoseriftc (Noto Serif CJK TC, static OTF)",
        "version": "Version 2.003;hotconv 1.1.1;makeotfexe 2.6.0",
        "sha256": "3ca2b3294ec84b795d0a45695e78e3612a44dce50f9fc776cd40206340a5768d"},
    "NotoSerifTC-Medium.otf": {
        "source": "https://github.com/google/fonts/tree/main/ofl/notoseriftc (Noto Serif CJK TC, static OTF)",
        "version": "Version 2.003;hotconv 1.1.1;makeotfexe 2.6.0",
        "sha256": "fd3936ff7cb87be3610d63a2d961ff06bd9ee2de9c0bb5a37890400487027e0f"},
    "LXGWWenKaiTC-Medium.ttf": {
        "source": "https://github.com/lxgw/LxgwWenkaiTC/releases/tag/v1.522",
        "version": "Version 1.522; March 17, 2026",
        "sha256": "94ca2870022fb8e4f90e2887524603690598142d17b620dfae318f1818ba8e17"},
    "DotGothic16-Regular.ttf": {
        "source": "https://github.com/google/fonts/tree/main/ofl/dotgothic16",
        "version": "Version 1.100",
        "sha256": "3ad9af88726d42b40f7f365f0dcac785af73cf20ea6f1d5b44e57cc21150b8f1"},
    "Anton-Regular.ttf": {
        "source": "https://github.com/google/fonts/tree/main/ofl/anton",
        "version": "Version 2.116; ttfautohint (v1.8.3)",
        "sha256": "a4ba3a92350ebb031da0cb47630ac49eb265082ca1bc0450442f4a83ab947cab",
        "commit": "a5573d2"},
    "Caveat-Variable.ttf": {
        "source": "https://github.com/google/fonts/tree/main/ofl/caveat (variable font, wght axis)",
        "version": "Version 2.000",
        "sha256": "0bdb6b660482d31531b3945849fba5916b3ef8695da7024a9e6b9ee3c4157988",
        "commit": "a5573d2"},
    "JetBrainsMono-Regular.ttf": {
        "source": "https://github.com/JetBrains/JetBrainsMono (Regular)",
        "version": "Version 2.304; ttfautohint (v1.8.4.7-5d5b)",
        "sha256": "a0bf60ef0f83c5ed4d7a75d45838548b1f6873372dfac88f71804491898d138f",
        "commit": "a5573d2"},
}

# Fonts that are subset, the Latin ones too. DotGothic16 is a Japanese font: it keeps what it has of the same set, and
# the app's Chinese characters it never had fall back to the system font exactly as before (CHECK_EXEMPT).
SUBSET = list(ORIGINALS)
CHECK_EXEMPT = {"DotGothic16-Regular.ttf"}
LATIN = {"Anton-Regular.ttf", "Caveat-Variable.ttf", "JetBrainsMono-Regular.ttf"}

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

# ETF names the repo already has; their CJK characters are always kept.
NAME_SOURCES = ["PocketCore/Sources/PocketCore/Resources/catalog.json", "WebPreview/etf-data.json"]
COMMON_CHARS = ROOT / "Scripts" / "common-chars.txt"

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


def name_characters() -> set[str]:
    """CJK characters of the ETF names in the bundled catalogue and etf-data.json (NFC)."""
    chars: set[str] = set()
    for name in NAME_SOURCES:
        path = ROOT / name
        if path.exists():
            chars |= {unicodedata.normalize("NFC", c) for c in path.read_text(encoding="utf-8") if is_cjk(c)}
    return chars


def insurance_characters(count: int | None = None) -> list[str]:
    """The first `count` (default INSURANCE) characters of common-chars.txt, most frequent first."""
    lines = [ln.strip() for ln in COMMON_CHARS.read_text(encoding="utf-8").splitlines()]
    return [ln for ln in lines if ln and not ln.startswith("#")][: INSURANCE if count is None else count]


def charset(insurance: int | None = None) -> set[str]:
    chars = {chr(cp) for lo, hi in RANGES for cp in range(lo, hi + 1)}
    chars |= big5_rows(range(0xA1, 0xA4))  # Big5 symbols
    chars |= app_characters()
    chars |= name_characters()
    chars |= set(insurance_characters(insurance))
    return chars


def original(name: str, source: Path | None) -> bytes:
    """The full font, from `--source` or git history, checked against its recorded sha256."""
    if source:
        path = source / name
        if not path.exists():
            raise SystemExit(f"{path} is missing. Put the full fonts ({', '.join(SUBSET)}) in that folder.")
        data = path.read_bytes()
    else:
        where = f"{ORIGINALS[name].get('commit', FULL_FONTS_COMMIT)}:App/Resources/Fonts/{name}"
        try:
            data = subprocess.run(["git", "show", where], cwd=ROOT, check=True, capture_output=True).stdout
        except (OSError, subprocess.CalledProcessError) as error:
            detail = getattr(error, "stderr", b"") or b""
            raise SystemExit(
                f"Could not read the full font {name} from git ({where}): "
                f"{detail.decode(errors='replace').strip() or error}\n"
                "The clone may be shallow (git fetch --unshallow) or the history rewritten. Get the original files "
                f"(see ORIGINALS for sources and sha256) and run: python Scripts/subset_fonts.py --source <dir>")
    digest = hashlib.sha256(data).hexdigest()
    if digest != ORIGINALS[name]["sha256"]:
        raise SystemExit(f"{name}: sha256 {digest} is not the recorded original {ORIGINALS[name]['sha256']} "
                         f"({ORIGINALS[name]['version']}). Refusing to subset a different file.")
    return data


def names(font: TTFont) -> list[tuple[int, int, int, int, str]]:
    """The standard name records (IDs below 256: family, style, full name, PostScript name, version, licence ...).
    Font-specific IDs (256+) name axes and features; the subsetter drops the ones nothing references any more."""
    return sorted((r.nameID, r.platformID, r.platEncID, r.langID, r.toUnicode()) for r in font["name"].names if r.nameID < 256)


def subset(source: Path | None) -> int:
    chars = charset()
    unicodes = sorted({ord(c) for c in chars})
    print(f"character set: {len(unicodes)} code points ({len({c for c in app_characters() if is_cjk(c)})} CJK in the app, "
          f"{len(name_characters())} CJK in ETF names, {len(insurance_characters())} insurance)")
    print(f"INSURANCE = {INSURANCE}")
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
    wanted |= name_characters()
    failed = False
    ascii_chars = {chr(cp) for cp in range(0x20, 0x7F)}
    for name in SUBSET:
        if name in LATIN:
            # All three originals had every printable ASCII character (checked when they were recorded), so each
            # subset must too. Needs no git history, which CI's shallow checkout lacks.
            cmap = TTFont(str(FONTS / name)).getBestCmap()
            gone = sorted(c for c in ascii_chars if ord(c) not in cmap)
            if gone:
                failed = True
                print(f"FAIL {name}: printable ASCII missing: {''.join(gone)}")
            else:
                print(f"ok   {name}: printable ASCII present")
            continue
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
        if name in CHECK_EXEMPT or name in LATIN:
            continue
        cmap = TTFont(str(FONTS / name)).getBestCmap()
        if any(ord(c) not in cmap for c in skin_chars):
            failed = True
            print(f"FAIL {name}: a skins.json character is missing")
    total = sum(p.stat().st_size for p in FONTS.iterdir() if p.suffix in {".ttf", ".otf"})
    if total > TOTAL_LIMIT:
        failed = True
        print(f"FAIL fonts total {total} bytes > {TOTAL_LIMIT}")
    else:
        print(f"ok   fonts total {total} bytes <= {TOTAL_LIMIT}")
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
