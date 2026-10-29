"""Compact the app's bundled catalogue, annual fees and official ETF distributions for the web preview.

Run from the repository root:  python -I WebPreview/build_data.py

Distributions come from the exchanges' open data (政府資料開放授權條款): TWSE 上市股票除權除息預告表 (TWT48U_ALL) for
listed ETFs and TPEx 上櫃股票除權除息預告表 for OTC ETFs. Both list upcoming ex-dividend dates and cash amounts only, with
no payment date, so each build adds them to the previous snapshot; a known ex-dividend date keeps its amount until the
notice sets one. sources["since"] is the day this record started: a snapshot without it still holds distributions
read from the TWSE website, which is not open data, so the record starts over. Frequencies need a full year in the
record (不配息 two), and dates more than about two years back are dropped.
If a source cannot be reached, the previous snapshot of that source is kept.
"""
import json
import re
import urllib.request
from datetime import date, timedelta
from pathlib import Path

root = Path(__file__).resolve().parent.parent
target = Path(__file__).resolve().parent / "etf-data.json"
catalog = json.loads((root / "App/Resources/catalog.json").read_text(encoding="utf-8"))
fees = json.loads((root / "App/Resources/annual-fees.json").read_text(encoding="utf-8"))
previous = json.loads(target.read_text(encoding="utf-8")) if target.exists() else {}

funds = [
    [f["id"], f["name"], f["strategy"], f.get("market") or "", f.get("fundType") or "", f.get("listingDate") or "", f.get("fullName") or ""]
    for f in catalog["funds"]
]
records = {
    code: [r["year"], r["total"], r["management"], r["custody"], r["commission"], r["tax"], r["subscriptionOffset"], r["guarantee"], r["other"], r["fundID"]]
    for code, r in sorted(fees["records"].items())
}
market = {f[0]: f[3] for f in funds}
listing = {f[0]: f[5] for f in funds}


def get_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (ETF ToGo data build)", "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def roc(text):
    """'115年10月22日' or '1151016' -> '2026-10-22'; anything else -> ''."""
    m = re.fullmatch(r"(\d{2,3})年(\d{1,2})月(\d{1,2})日", (text or "").strip()) or re.fullmatch(r"(\d{3})(\d{2})(\d{2})", (text or "").strip())
    if not m:
        return ""
    y, mo, d = (int(x) for x in m.groups())
    try:
        return date(y + 1911, mo, d).isoformat()
    except ValueError:
        return ""


def amount(text):
    try:
        value = float(str(text).replace(",", ""))
        return value if value > 0 else None
    except (TypeError, ValueError):
        return None


today = date.today()
old = previous.get("dividends") or {}
since = (old.get("sources") or {}).get("since")
if not since:
    old, since = {}, today.isoformat()
events = {sym: {item[0]: list(item) for item in items} for sym, items in (old.get("events") or {}).items() if sym in market}
sources = {"since": since}

NOTICES = [
    # (source, market, URL, code field, ex-date field, kind field)
    ("twse", "TWSE", "https://openapi.twse.com.tw/v1/exchangeReport/TWT48U_ALL", "Code", "Date", "Exdividend"),
    ("tpex", "TPEx", "https://www.tpex.org.tw/openapi/v1/tpex_exright_prepost", "SecuritiesCompanyCode", "ExRrightsExDividendDate", "ExRrightsExDividend"),
]
for key, wanted, url, code_field, day_field, kind_field in NOTICES:
    try:
        rows = get_json(url)
        if not isinstance(rows, list) or (rows and not {code_field, day_field} <= set(rows[0])):
            raise ValueError(f"unexpected {key} response")
        for row in rows:
            sym, ex = str(row.get(code_field, "")).strip(), roc(row.get(day_field))
            if market.get(sym) == wanted and ex and "息" in str(row.get(kind_field, "")):
                known = events.setdefault(sym, {}).get(ex)
                value = amount(row.get("CashDividend"))
                events[sym][ex] = [ex, "", value if value is not None else (known[2] if known else None)]
        sources[key] = today.isoformat()
    except Exception as error:  # keep the previous snapshot of this source
        print(f"{wanted} distributions not refreshed:", error)
        if (old.get("sources") or {}).get(key):
            sources[key] = old["sources"][key]

oldest = (today - timedelta(days=760)).isoformat()
for sym in list(events):
    events[sym] = sorted((item for item in events[sym].values() if item[0] >= oldest), key=lambda item: item[0], reverse=True)
    if not events[sym]:
        del events[sym]


def frequency(sym):
    """Distribution frequency from the number of ex-dividend dates in the past year (listed ETFs only), once the
    record covers that year."""
    year_ago = (today - timedelta(days=365)).isoformat()
    if market.get(sym) != "TWSE" or "twse" not in sources or since > year_ago:
        return None
    n = sum(1 for ex, _, _ in events.get(sym, []) if year_ago < ex <= today.isoformat())
    if n >= 9:
        return "月配"
    if n >= 5:
        return "雙月配"
    if n >= 3:
        return "季配"
    if n == 2:
        return "半年配"
    if n == 1:
        return "年配"
    listed = listing.get(sym) or ""
    two_years_ago = (today - timedelta(days=730)).isoformat()
    if not events.get(sym) and since <= two_years_ago and listed and listed <= two_years_ago:
        return "不配息"
    return None


freq = {sym: label for sym in market if (label := frequency(sym))}
out = {
    "catalog": {"listedDate": catalog["listedDate"], "fetchedDay": catalog["fetchedDay"], "funds": funds},
    "fees": {"fetchedDay": fees["fetchedDay"], "sourceURL": fees["sourceURL"], "records": records},
    "dividends": {"sources": sources, "events": events, "freq": freq},
}
target.write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
# The iPhone app bundles the same snapshot in a shape Codable can read directly.
native = {
    "sources": sources,
    "events": {sym: [{"ex": ex, "pay": pay, "amount": value} for ex, pay, value in items] for sym, items in sorted(events.items())},
    "freq": dict(sorted(freq.items())),
}
(root / "App/Resources/official-dividends.json").write_text(json.dumps(native, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(f"{len(funds)} funds, {len(records)} fee records, {sum(len(v) for v in events.values())} distributions for {len(events)} ETFs, "
      f"{len(freq)} frequencies -> {target.name} ({target.stat().st_size // 1024} KB)")
