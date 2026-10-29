"""Build reviewed app snapshots from saved official responses; no fuzzy name matching.

Usage: python Scripts/build_reference_snapshot.py INPUT_DIR YYYY-MM-DD
INPUT_DIR contains the exchanges' open data listed.json (TWSE t187ap47_L 基金基本資料彙總表),
twse-quotes.json (TWSE STOCK_DAY_ALL) and tpex-quotes.json (TPEx tpex_mainboard_quotes), plus
fees-2025-annual.html. ETFs are the codes starting with 00 that trade on either exchange. The open
data has no full name, fund type or listing date for OTC ETFs, so those carry over from the current
App/Resources/catalog.json.
The SITCA form must have year=2025 and period=Year selected. When changing
year, query once to refresh the period options, then query Year again.
"""
import hashlib
import html
import json
import re
import sys
import unicodedata
from datetime import date
from html.parser import HTMLParser
from pathlib import Path

source = Path(sys.argv[1])
today = date.fromisoformat(sys.argv[2]).isoformat()
dest = Path(__file__).resolve().parents[1] / 'App' / 'Resources'
def load(name): return json.loads((source / name).read_bytes().removeprefix(b'\xef\xbb\xbf'))
def clean(name): return html.unescape(name)
def day(raw):
    raw = re.sub(r'\D', '', raw)
    year = int(raw[:-4]) + (1911 if len(raw) == 7 else 0)
    return date(year, int(raw[-4:-2]), int(raw[-2:])).isoformat()
def strategy(name):
    if any(x in name for x in ['正2','反1','槓桿','反向']): return '老虎機'
    if any(x in name for x in ['高股息','優息','高息']): return '印鈔機'
    if name in ['元大台灣50','富邦台50','元大富櫃50']: return '存錢筒'
    return '待分類'
details = {x['基金代號'].strip(): x for x in load('listed.json')}
known = {x['id']: x for x in json.loads((dest/'catalog.json').read_text(encoding='utf-8'))['funds']} if (dest/'catalog.json').exists() else {}
funds = []
for market, filename, code_key, name_key in [('TWSE','twse-quotes.json','Code','Name'),('TPEx','tpex-quotes.json','SecuritiesCompanyCode','CompanyName')]:
    rows = load(filename)
    assert rows and code_key in rows[0] and name_key in rows[0]
    count = len(funds)
    for item in rows:
        code = item[code_key].strip(); name = clean(item[name_key].strip())
        if not re.fullmatch(r'00[0-9]{2,4}[A-Z]?', code): continue
        fund = dict(id=code,name=name,strategy=strategy(name),market=market)
        if market == 'TWSE' and code in details:
            fund.update(listingDate=day(details[code]['上市日期']),fullName=clean(details[code]['基金中文名稱']),fundType=details[code]['基金類型'])
        else:
            fund.update({k: known[code][k] for k in ['listingDate','fullName','fundType'] if known.get(code,{}).get(k)})
        funds.append(fund)
    assert len(funds) > count
assert len(set(x['id'] for x in funds)) == len(funds)
catalog = dict(funds=sorted(funds,key=lambda x:x['id']),listedDate=max(day(x['出表日期']) for x in details.values()),fetchedDay=today,
               sources=['https://openapi.twse.com.tw/v1/opendata/t187ap47_L','https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL','https://www.tpex.org.tw/openapi/v1/tpex_mainboard_quotes'])
class Table(HTMLParser):
    def __init__(self): super().__init__(); self.rows=[]; self.row=[]; self.cell=None
    def handle_starttag(self, tag, attrs):
        if tag=='tr': self.row=[]
        if tag in ['td','th']: self.cell=[]
    def handle_endtag(self, tag):
        if tag in ['td','th'] and self.cell is not None: self.row.append(' '.join(''.join(self.cell).split())); self.cell=None
        if tag=='tr' and self.row: self.rows.append(self.row)
    def handle_data(self, data):
        if self.cell is not None: self.cell.append(data)
report = (source/'fees-2025-annual.html').read_text(encoding='utf-8')
assert re.search(r'<option selected="selected" value="Year">',report)
assert re.search(r'<option selected="selected" value="2025">',report)
assert '2025/12/31' in report
table = Table(); table.feed(report)
rows = [r for r in table.rows if len(r)==19 and re.fullmatch('[0-9]{8}',r[1])]
by_id = {}
for row in rows:
    if row[1] in by_id: assert by_id[row[1]] == row
    by_id[row[1]] = row
rows = list(by_id.values())
def normalize(name):
    name = unicodedata.normalize('NFKC',name).replace('臺','台').replace('證券投資信託','')
    name = re.split(r'\(本基|\(基金|\(本子|\(原名',name)[0]
    name = re.sub(r'^.*傘型基金之','',name)
    return re.sub(r'\s+','',name)
by_name = {}
for row in rows: by_name.setdefault(normalize(row[2]),[]).append(row)
records = {}; matches = []
for fund in funds:
    row = None; method = ''
    if fund['market']=='TWSE':
        row = by_id.get(details.get(fund['id'],{}).get('基金統一編號'))
        method = 'official fund tax ID'
    elif fund.get('fullName'):
        candidates = by_name.get(normalize(fund['fullName']),[])
        if len(candidates)==1: row = candidates[0]
        method = 'unique exact normalized official child fund name'
    if row is None: continue
    values = [float(row[i].removesuffix('%')) for i in range(4,19,2)]
    assert all(0 <= x <= 100 for x in values)
    records[fund['id']] = dict(symbol=fund['id'],fundID=row[1],fundName=row[2],year=2025,
        **dict(zip(['commission','tax','subscriptionOffset','management','custody','guarantee','other','total'],values)))
    matches.append(dict(symbol=fund['id'],fundID=row[1],method=method,officialName=fund.get('fullName'),reportName=row[2]))
fees = dict(fetchedDay=today,sourceURL='https://www.sitca.org.tw/ROC/Industry/IN2211.aspx?pid=IN2222_01',records=records)
for filename, data in [('catalog.json',catalog),('annual-fees.json',fees)]:
    (dest/filename).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
evidence = Path(__file__).resolve().parents[1]/'Evidence'/'ReferenceData'
evidence.mkdir(parents=True,exist_ok=True)
receipt = dict(fetchedDay=today,activeCodes=len(funds),listed=sum(x['market']=='TWSE' for x in funds),otc=sum(x['market']=='TPEx' for x in funds),annualFeeCoverage=len(records),
    sourceSHA256={str(p.relative_to(source)):hashlib.sha256(p.read_bytes()).hexdigest() for p in source.glob('*') if p.name in ['listed.json','twse-quotes.json','tpex-quotes.json','fees-2025-annual.html']},
    matches=matches,missing=[x['id'] for x in funds if x['id'] not in records])
(evidence/'snapshot-receipt.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:receipt[k] for k in ['activeCodes','listed','otc','annualFeeCoverage']},ensure_ascii=False))
