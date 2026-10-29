"""Build the standalone web app (GitHub Pages) from WebPreview/index.html.

The Claude artifact version is published from index.html as-is; this wraps the same
page in a full document with the app icon and home-screen metadata.

Usage, from the repository root:  python -I WebPreview/build_pages.py <output-dir>
"""
import hashlib
import io
import json
import plistlib
import shutil
import sys
import uuid
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

here = Path(__file__).resolve().parent
root = here.parent
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)

# The home-screen icon is the iPhone app icon (blue, full bleed; iOS rounds the corners).
app_icon = root / "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
# iOS keeps a home-screen icon per URL, so icon and manifest names carry the icon's content hash:
# a new icon gets new URLs and is fetched again when the page is re-added to the home screen.
# Bump ICON_REVISION to force new icon URLs when the image is unchanged but iOS kept a bad copy.
ICON_REVISION = b"2"
version = hashlib.sha256(app_icon.read_bytes() + ICON_REVISION).hexdigest()[:8]
icons = {size: f"icon-{version}-{size}.png" for size in (180, 192, 512)}
# Absolute URLs: the home-screen sheet resolves icons outside the page, so nothing depends on the base URL.
site = "https://sonia6891.github.io/etftogo-web/"
manifest_name = f"manifest-{version}.webmanifest"
# Link previews (LINE, iMessage, Facebook) show this card, so a shared link carries the app icon.
share_name = f"share-{version}.png"
for stale in [*out.glob("icon-*.png"), *out.glob("manifest*.webmanifest"), *out.glob("share-*.png")]:
    stale.unlink()

page = (here / "index.html").read_text(encoding="utf-8")
# index.html starts with its own charset/viewport lines for local testing; the wrapper supplies them.
lines = [line for line in page.splitlines() if not line.startswith("<meta charset") and not line.startswith('<meta name="viewport"')]
title = next(line for line in lines if line.startswith("<title>"))
description = "投資袋著走：台股與 ETF 的持有、配息與組合試算。"
lines.remove(title)
head = "\n".join([
    "<!doctype html>",
    '<html lang="zh-Hant">',
    "<head>",
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">',
    title,
    '<meta name="apple-mobile-web-app-capable" content="yes">',
    '<meta name="mobile-web-app-capable" content="yes">',
    '<meta name="apple-mobile-web-app-title" content="投資袋著走">',
    '<meta name="apple-mobile-web-app-status-bar-style" content="default">',
    '<meta name="theme-color" content="#edf2ff" media="(prefers-color-scheme: light)">',
    '<meta name="theme-color" content="#0e1628" media="(prefers-color-scheme: dark)">',
    f'<meta name="description" content="{description}">',
    '<meta property="og:type" content="website">',
    '<meta property="og:site_name" content="投資袋著走">',
    '<meta property="og:title" content="投資袋著走">',
    f'<meta property="og:description" content="{description}">',
    f'<meta property="og:url" content="{site}">',
    f'<meta property="og:image" content="{site}{share_name}">',
    '<meta property="og:image:type" content="image/png">',
    '<meta property="og:image:width" content="1200">',
    '<meta property="og:image:height" content="630">',
    '<meta property="og:image:alt" content="投資袋著走 App 圖示">',
    '<meta name="twitter:card" content="summary_large_image">',
    f'<meta name="twitter:image" content="{site}{share_name}">',
    f'<link rel="apple-touch-icon" sizes="180x180" href="{site}{icons[180]}">',
    f'<link rel="apple-touch-icon-precomposed" sizes="180x180" href="{site}{icons[180]}">',
    f'<link rel="icon" type="image/png" sizes="192x192" href="{site}{icons[192]}">',
    f'<link rel="manifest" href="{site}{manifest_name}">',
    "<style>html,body{margin:0;height:100%}</style>",
    "</head>",
    "<body>",
])
(out / "index.html").write_text(head + "\n" + "\n".join(lines) + "\n</body>\n</html>\n", encoding="utf-8")

icon = Image.open(app_icon).convert("RGB")
for size, name in icons.items():
    icon.resize((size, size), Image.LANCZOS).save(out / name, optimize=True)
# Fallbacks for clients that probe the conventional names instead of reading the links.
for name in ("apple-touch-icon.png", "apple-touch-icon-precomposed.png", "apple-touch-icon-180x180.png"):
    icon.resize((180, 180), Image.LANCZOS).save(out / name, optimize=True)
icon.save(out / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])

def share_card():
    """1200x630: the icon with iOS-style corners on the app's light background and the name under it, all inside
    the centre square that LINE crops to."""
    width, height, size = 1200, 630, 400
    top, bottom = (246, 249, 255), (219, 230, 255)
    column = Image.new("RGB", (1, height))
    for y in range(height):
        t = y / (height - 1)
        column.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    card = column.resize((width, height)).convert("RGBA")
    x, y, radius = (width - size) // 2, 62, round(size * 0.2237)
    shadow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x + 6, y + 22, x + size - 6, y + size + 22), radius=radius, fill=(0, 70, 200, 80))
    card = Image.alpha_composite(card, shadow.filter(ImageFilter.GaussianBlur(26)))
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), radius=radius * 4, fill=255)
    card.paste(Image.open(app_icon).convert("RGB").resize((size, size), Image.LANCZOS), (x, y), mask.resize((size, size), Image.LANCZOS))
    fonts = [Path("C:/Windows/Fonts/msjhbd.ttc"), Path("/System/Library/Fonts/PingFang.ttc"), Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc")]
    font_path = next((p for p in fonts if p.exists()), None)
    if font_path:
        draw = ImageDraw.Draw(card)
        font = ImageFont.truetype(str(font_path), 66)
        name = "投資袋著走"
        draw.text(((width - draw.textlength(name, font=font)) / 2, y + size + 34), name, font=font, fill=(21, 33, 66))
    return card.convert("RGB")

share_card().save(out / share_name, optimize=True)

manifest = {
    "id": "./",
    "name": "投資袋著走",
    "short_name": "投資袋著走",
    "lang": "zh-Hant",
    "start_url": "./",
    "scope": "./",
    "display": "standalone",
    "background_color": "#edf2ff",
    "theme_color": "#edf2ff",
    "icons": [
        {"src": site + icons[180], "sizes": "180x180", "type": "image/png", "purpose": "any"},
        {"src": site + icons[192], "sizes": "192x192", "type": "image/png", "purpose": "any"},
        {"src": site + icons[512], "sizes": "512x512", "type": "image/png", "purpose": "any"},
    ],
}
(out / manifest_name).write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")

# A Web Clip configuration profile puts the app on the home screen with this exact icon, without relying on
# Safari to fetch it. It holds only the web clip; the viewer installs it in Settings and can remove it there.
clip_png = io.BytesIO()
icon.resize((400, 400), Image.LANCZOS).save(clip_png, format="PNG", optimize=True)
clip = {
    "PayloadType": "com.apple.webClip.managed", "PayloadVersion": 1,
    "PayloadIdentifier": "io.github.sonia6891.etftogo.webclip",
    "PayloadUUID": str(uuid.uuid5(uuid.NAMESPACE_URL, site + "#webclip")).upper(),
    "PayloadDisplayName": "投資袋著走 主畫面圖示",
    "Label": "投資袋著走", "URL": site, "Icon": clip_png.getvalue(),
    "FullScreen": True, "IsRemovable": True, "Precomposed": True,
}
profile = {
    "PayloadType": "Configuration", "PayloadVersion": 1,
    "PayloadIdentifier": "io.github.sonia6891.etftogo",
    "PayloadUUID": str(uuid.uuid5(uuid.NAMESPACE_URL, site + "#profile")).upper(),
    "PayloadDisplayName": "投資袋著走",
    "PayloadDescription": "在主畫面加入 投資袋著走網頁 App（藍底口袋圖示）。只包含一個主畫面圖示，不會變更其他設定。",
    "PayloadRemovalDisallowed": False,
    "PayloadContent": [clip],
}
(out / "ETFToGo.mobileconfig").write_bytes(plistlib.dumps(profile))
shutil.copyfile(here / "etf-data.json", out / "etf-data.json")
shutil.copyfile(here / "stock-data.json", out / "stock-data.json")
# Illustrations (made with Figma AI, prepared by prepare_art.py) are referenced as assets/<name>.png.
shutil.copytree(here / "assets", out / "assets", dirs_exist_ok=True)
(out / ".nojekyll").write_text("", encoding="utf-8")
print("built", sorted(p.name for p in out.iterdir()))
