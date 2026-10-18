"""Bundle Taiwan listed (TWSE) and OTC (TPEx) stocks, daily closes and the two market indices for the app.

Run from the repository root:  python -I WebPreview/build_stocks.py

Everything comes from the exchanges' free open data, which browsers cannot read directly (no CORS), so the app
ships this snapshot and shows its date. Live prices still come from the viewer's own Fugle key.

- Companies: TWSE t187ap03_L and TPEx mopsfin_t187ap03_O (name, full name, industry, listing date).
- Closes: TWSE STOCK_DAY_ALL and TPEx daily close quotes, for stocks and ETFs, from the last trading day.
- Indices: TAIEX from TWSE MI_INDEX and MI_5MINS_HIST (this month's daily closes), TPEx index from tpex_index.
  History is merged with the previous snapshot, so it grows on every build.
- Monthly revenue (t187ap05), latest quarterly EPS (t187ap06 *_ci), latest dividend decision (TWSE t187ap45_L),
  upcoming ex-dates (TWT48U_ALL, TPEx prepost) and past ex-dates (about two years), merged with the previous
  snapshot: TPEx publishes its results table (tpex_exright_daily); TWSE's results table is not open data, so its
  past ex-dates come from the notice on the day, with the cash dividend of a pure ex-dividend as the value.
"since" holds the day the TAIEX and ex-date histories started from open data alone. Snapshots without it also held
figures from the TWSE website (FMTQIK, TWT49U), which is not open data, so those histories start over.
If a source cannot be reached, that part of the previous snapshot is kept.
"""
import json
import re
import urllib.request
from datetime import date, timedelta
from pathlib import Path

root = Path(__file__).resolve().parent.parent
target = Path(__file__).resolve().parent / "stock-data.json"
native_target = root / "App/Resources/stock-data.json"
catalog = json.loads((root / "App/Resources/catalog.json").read_text(encoding="utf-8"))
etf_ids = {f["id"] for f in catalog["funds"]}
previous = json.loads(target.read_text(encoding="utf-8")) if target.exists() else {}
since = dict(previous.get("since") or {})
today = date.today()


def get_json(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (ETF ToGo data build)", "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=90) as response:
        return json.loads(response.read().decode("utf-8"))


def roc_day(text):
    """'1151015', '115/10/15' or '115年10月15日' -> '2026-10-15'; anything else -> ''."""
    t = (text or "").strip()
    m = re.fullmatch(r"(\d{2,3})(\d{2})(\d{2})", t) or re.fullmatch(r"(\d{2,3})[/年](\d{1,2})[/月](\d{1,2})日?", t)
    if not m:
        return ""
    y, mo, d = (int(x) for x in m.groups())
    try:
        return date(y + 1911, mo, d).isoformat()
    except ValueError:
        return ""


def ad_day(text):
    t = (text or "").strip()
    return f"{t[:4]}-{t[4:6]}-{t[6:8]}" if re.fullmatch(r"\d{8}", t) else ""


def number(text):
    try:
        return float(str(text).replace(",", "").strip())
    except (TypeError, ValueError):
        return None


def keep(key, error):
    print(f"{key} not refreshed:", error)
    return previous.get(key)


# Industry codes shared by both exchanges; names in the revenue datasets take precedence when present.
INDUSTRY = {
    "01": "水泥工業", "02": "食品工業", "03": "塑膠工業", "04": "紡織纖維", "05": "電機機械", "06": "電器電纜",
    "08": "玻璃陶瓷", "09": "造紙工業", "10": "鋼鐵工業", "11": "橡膠工業", "12": "汽車工業", "14": "建材營造",
    "15": "航運業", "16": "觀光餐旅", "17": "金融保險", "18": "貿易百貨", "19": "綜合", "20": "其他業",
    "21": "化學工業", "22": "生技醫療業", "23": "油電燃氣業", "24": "半導體業", "25": "電腦及週邊設備業",
    "26": "光電業", "27": "通信網路業", "28": "電子零組件業", "29": "電子通路業", "30": "資訊服務業",
    "31": "其他電子業", "32": "文化創意業", "33": "農業科技業", "34": "電子商務", "35": "綠能環保",
    "36": "數位雲端", "37": "運動休閒", "38": "居家生活", "80": "管理股票", "91": "存託憑證",
}

# ---- companies ----
stocks = previous.get("stocks") or []
industries = previous.get("industries") or []
try:
    twse_co = get_json("https://openapi.twse.com.tw/v1/opendata/t187ap03_L")
    tpex_co = get_json("https://www.tpex.org.tw/openapi/v1/mopsfin_t187ap03_O")
    rows = []
    for x in twse_co:
        rows.append((x["公司代號"].strip(), x["公司簡稱"].strip(), 1, (x.get("產業別") or "").strip(), x["公司名稱"].strip(), ad_day(x.get("上市日期"))))
    for x in tpex_co:
        rows.append((x["SecuritiesCompanyCode"].strip(), x["CompanyAbbreviation"].strip(), 2, (x.get("SecuritiesIndustryCode") or "").strip(), x["CompanyName"].strip(), ad_day(x.get("DateOfListing"))))
    rows = [r for r in rows if re.fullmatch(r"[0-9A-Z]{4,6}", r[0]) and r[0] not in etf_ids]
    rows.sort(key=lambda r: (len(r[0]), r[0]))
    industries, stocks = [], []
    for code, name, market, ind, full, listed in rows:
        label = INDUSTRY.get(ind, "其他")
        if label not in industries:
            industries.append(label)
        stocks.append([code, name, market, industries.index(label), full, listed])
except Exception as error:  # keep the previous company list
    print("companies not refreshed:", error)

stock_ids = {s[0] for s in stocks}

# ---- daily closes for stocks and ETFs ----
close, close_date = previous.get("close") or {}, previous.get("closeDate") or {}
try:
    fresh, dates = {}, {}
    for x in get_json("https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL"):
        code = x["Code"].strip()
        c = number(x["ClosingPrice"])
        if (code in stock_ids or code in etf_ids) and c and c > 0:
            fresh[code] = [c, number(x["Change"]), number(x["OpeningPrice"]), number(x["HighestPrice"]), number(x["LowestPrice"]), number(x["TradeVolume"]), number(x["TradeValue"])]
            dates["twse"] = roc_day(x["Date"]) or dates.get("twse", "")
    for x in get_json("https://www.tpex.org.tw/openapi/v1/tpex_mainboard_daily_close_quotes"):
        code = x["SecuritiesCompanyCode"].strip()
        c = number(x["Close"])
        if (code in stock_ids or code in etf_ids) and c and c > 0:
            fresh[code] = [c, number(x["Change"]), number(x["Open"]), number(x["High"]), number(x["Low"]), number(x["TradingShares"]), number(x["TransactionAmount"])]
            dates["tpex"] = roc_day(x["Date"]) or dates.get("tpex", "")
    if len(fresh) > 1000:
        close, close_date = fresh, dates
except Exception as error:
    print("closes not refreshed:", error)

# ---- indices ----
index = previous.get("index") or {}


def merged(old, new):
    points = {d: v for d, v in (old or [])}
    points.update({d: v for d, v in new})
    return sorted(points.items())[-500:]


taiex = index.get("taiex") or {"name": "加權指數", "hist": []}
if "taiex" not in since:  # the latest close came from MI_INDEX; only the history goes
    taiex["hist"], since["taiex"] = [], today.isoformat()
    index["taiex"] = taiex
try:
    # 發行量加權股價指數歷史資料 covers the current month only; earlier months come from the previous snapshot.
    new = []
    for x in get_json("https://openapi.twse.com.tw/v1/indicesReport/MI_5MINS_HIST"):
        d, v = roc_day(x.get("Date")), number(x.get("ClosingIndex"))
        if d and v:
            new.append((d, v))
    taiex["hist"] = [list(p) for p in merged(taiex.get("hist"), new)]
    for x in get_json("https://openapi.twse.com.tw/v1/exchangeReport/MI_INDEX"):
        if x.get("指數") == "發行量加權股價指數":
            pts = number(x["漲跌點數"]) or 0
            sign = -1 if x.get("漲跌") == "-" else 1
            taiex.update({"date": roc_day(x["日期"]), "close": number(x["收盤指數"]), "change": sign * pts, "pct": number(x["漲跌百分比"])})
            if taiex["date"] and taiex["close"]:
                taiex["hist"] = [list(p) for p in merged(taiex["hist"], [(taiex["date"], taiex["close"])])]
    index["taiex"] = taiex
except Exception as error:
    print("TAIEX not refreshed:", error)

tpex_ix = index.get("tpex") or {"name": "櫃買指數", "hist": []}
try:
    rows = get_json("https://www.tpex.org.tw/openapi/v1/tpex_index")
    new = [(ad_day(x["Date"]), number(x["Close"])) for x in rows if ad_day(x["Date"]) and number(x["Close"])]
    tpex_ix["hist"] = [list(p) for p in merged(tpex_ix.get("hist"), new)]
    last = max(rows, key=lambda x: x["Date"])
    c, ch = number(last["Close"]), number(last["Change"])
    tpex_ix.update({"date": ad_day(last["Date"]), "close": c, "change": ch, "pct": round(ch / (c - ch) * 100, 2) if c and ch is not None and c != ch else None})
    index["tpex"] = tpex_ix
except Exception as error:
    print("TPEx index not refreshed:", error)

# ---- monthly revenue (thousand NT$) ----
revenue = previous.get("revenue") or {}
try:
    fresh = {}
    for url in ["https://openapi.twse.com.tw/v1/opendata/t187ap05_L", "https://www.tpex.org.tw/openapi/v1/mopsfin_t187ap05_O"]:
        for x in get_json(url):
            ym = x.get("資料年月", "")
            if not re.fullmatch(r"\d{5}", ym):
                continue
            fresh[x["公司代號"].strip()] = [f"{int(ym[:3]) + 1911}-{ym[3:]}", number(x["營業收入-當月營收"]), number(x["營業收入-上月比較增減(%)"]),
                                           number(x["營業收入-去年同月增減(%)"]), number(x["累計營業收入-當月累計營收"]), number(x["累計營業收入-前期比較增減(%)"])]
    if fresh:
        revenue = fresh
except Exception as error:
    print("revenue not refreshed:", error)

# ---- latest quarterly EPS (cumulative for the year, as reported) ----
eps = previous.get("eps") or {}
try:
    fresh = {}
    for suffix in ["ci", "basi", "bd", "fh", "ins", "mim"]:
        for url in [f"https://openapi.twse.com.tw/v1/opendata/t187ap06_L_{suffix}", f"https://www.tpex.org.tw/openapi/v1/mopsfin_t187ap06_O_{suffix}"]:
            try:
                rows = get_json(url)
            except Exception:
                continue
            for x in rows:
                code = (x.get("公司代號") or x.get("SecuritiesCompanyCode") or "").strip()
                year, season = x.get("年度") or x.get("Year"), x.get("季別") or x.get("Season")
                v = number(x.get("基本每股盈餘（元）"))
                if code and year and season and v is not None:
                    fresh[code] = [int(year) + 1911, int(season), v]
    if fresh:
        eps = fresh
except Exception as error:
    print("EPS not refreshed:", error)

# ---- dividends ----
policy = previous.get("divPolicy") or {}
try:
    fresh = {}
    for x in get_json("https://openapi.twse.com.tw/v1/opendata/t187ap45_L"):
        cash = sum(number(x.get(k)) or 0 for k in ["股東配發-盈餘分配之現金股利(元/股)", "股東配發-法定盈餘公積發放之現金(元/股)", "股東配發-資本公積發放之現金(元/股)"])
        stock = sum(number(x.get(k)) or 0 for k in ["股東配發-盈餘轉增資配股(元/股)", "股東配發-法定盈餘公積轉增資配股(元/股)", "股東配發-資本公積轉增資配股(元/股)"])
        code = x["公司代號"].strip()
        item = [x.get("股利年度", "").strip(), x.get("股利所屬年(季)度", "").strip(), round(cash, 6), round(stock, 6), roc_day(x.get("股東會日期")), x.get("決議（擬議）進度", "").strip()]
        fresh.setdefault(code, []).append(item)
    if fresh:
        policy = fresh
except Exception as error:
    print("dividend policy not refreshed:", error)

ex_hist = previous.get("exHist") or {}
if "exHist" not in since:
    ex_hist, since["exHist"] = {}, today.isoformat()
try:
    happened = []  # (code, ex-date, 權值＋息值 or None, 息 / 權 / 權息)
    for x in get_json("https://openapi.twse.com.tw/v1/exchangeReport/TWT48U_ALL"):
        kind = str(x.get("Exdividend") or "").strip()
        # The 權值 of a stock dividend depends on the price before the ex-date, which the notice does not give.
        happened.append((x["Code"].strip(), roc_day(x["Date"]), number(x.get("CashDividend")) if kind == "息" else None, kind))
    for x in get_json("https://www.tpex.org.tw/openapi/v1/tpex_exright_daily"):
        happened.append((x["SecuritiesCompanyCode"].strip(), roc_day(x["Date"]), number(x.get("StockDividendPlusCashDividend")),
                         str(x.get("ExRightsDiviend") or "").strip().replace("除", "")))
    fresh = {code: {e[0]: e for e in items} for code, items in ex_hist.items()}
    for code, d, v, kind in happened:
        if (code in stock_ids or code in etf_ids) and d and d <= today.isoformat() and kind and (v is not None or kind != "息"):
            fresh.setdefault(code, {})[d] = [d, v, kind]
    oldest = (today - timedelta(days=730)).isoformat()
    kept = {}
    for code, by_day in fresh.items():
        items = sorted((e for e in by_day.values() if e[0] >= oldest), key=lambda e: e[0], reverse=True)
        if items:
            kept[code] = items
    ex_hist = kept
except Exception as error:
    print("ex-dividend history not refreshed:", error)

ex_next = {}
try:
    for x in get_json("https://openapi.twse.com.tw/v1/exchangeReport/TWT48U_ALL"):
        code, d = x["Code"].strip(), roc_day(x["Date"])
        if code in stock_ids and d >= today.isoformat():
            ex_next.setdefault(code, []).append([d, number(x.get("CashDividend")), (x.get("Exdividend") or "").strip()])
    for x in get_json("https://www.tpex.org.tw/openapi/v1/tpex_exright_prepost"):
        code, d = str(x.get("SecuritiesCompanyCode", "")).strip(), roc_day(x.get("ExRrightsExDividendDate"))
        if code in stock_ids and d >= today.isoformat():
            ex_next.setdefault(code, []).append([d, number(x.get("CashDividend")), str(x.get("ExRrightsExDividend", "")).strip()])
except Exception as error:
    ex_next = keep("exNext", error) or {}

out = {
    "fetchedDay": today.isoformat(), "closeDate": close_date, "industries": industries, "stocks": stocks, "close": close,
    "index": index, "revenue": revenue, "eps": eps, "divPolicy": policy, "exHist": ex_hist, "exNext": ex_next, "since": since,
}
text = json.dumps(out, ensure_ascii=False, separators=(",", ":"))
target.write_text(text, encoding="utf-8")
native_target.write_text(text, encoding="utf-8")
print(f"{len(stocks)} stocks in {len(industries)} industries, {len(close)} closes {close_date}, TAIEX {len(index.get('taiex', {}).get('hist', []))} days, "
      f"TPEx {len(index.get('tpex', {}).get('hist', []))} days, {len(revenue)} revenue, {len(eps)} EPS, {len(policy)} policies, "
      f"{len(ex_hist)} ex histories, {len(ex_next)} upcoming -> {target.name} ({target.stat().st_size // 1024} KB)")
