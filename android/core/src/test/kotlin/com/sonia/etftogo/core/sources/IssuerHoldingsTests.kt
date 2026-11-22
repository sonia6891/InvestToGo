package com.sonia.etftogo.core.sources

import com.sonia.etftogo.core.Fixtures
import com.sonia.etftogo.core.models.ComponentSnapshot
import com.sonia.etftogo.core.support.AppDataError
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class IssuerHoldingsTests {
    private fun fx(n: String) = Fixtures.bytes("member/issuers/$n")
    private fun json(s: String) = s.toByteArray()
    private fun fails(block: () -> Any) = assertFailsWith<AppDataError> { block() }

    private fun assertSnapshot(s: ComponentSnapshot, issuer: Issuer, symbol: String, date: String, count: Int, first: Triple<String, String, Double>) {
        assertEquals(symbol, s.symbol)
        assertEquals(date, s.date)
        assertEquals(issuer.displayName, s.source)
        assertEquals(count, s.components.size)
        assertEquals(first.first, s.components.first().symbol)
        assertEquals(first.second, s.components.first().name)
        assertEquals(first.third, s.components.first().weight, 1e-9)
        s.validate()
    }

    // Issuers

    @Test fun issuerNames() {
        assertEquals(listOf("元大投信", "國泰投信", "富邦投信", "群益投信", "復華投信", "中國信託投信"), Issuer.entries.map { it.displayName })
        assertEquals(Issuer.FHTRUST, Issuer.entries.first { it.rawValue == "fhtrust" })
    }

    @Test fun issuerByName() {
        assertEquals(Issuer.YUANTA, IssuerDirectory.issuer("元大台灣50"))
        assertEquals(Issuer.CATHAY, IssuerDirectory.issuer("國泰永續高股息"))
        assertEquals(Issuer.FUBON, IssuerDirectory.issuer("富邦台50"))
        assertEquals(Issuer.CAPITAL, IssuerDirectory.issuer("群益台灣精選高息"))
        assertEquals(Issuer.FHTRUST, IssuerDirectory.issuer("復華台灣科技優息"))
        assertEquals(Issuer.CTBC, IssuerDirectory.issuer("中信關鍵半導體"))
        assertEquals(Issuer.CTBC, IssuerDirectory.issuer(" 中國信託臺灣優選成長高股息"))
        assertNull(IssuerDirectory.issuer("統一台灣高息動能"))
        assertNull(IssuerDirectory.issuer(""))
    }

    /** Active ETFs carry 「主動」 in front of the company's name. */
    @Test fun issuerOfActiveFunds() {
        assertEquals(Issuer.CAPITAL, IssuerDirectory.issuer("主動群益台灣強棒"))
        assertEquals(Issuer.YUANTA, IssuerDirectory.issuer("主動元大台灣優息"))
        assertEquals(Issuer.CATHAY, IssuerDirectory.issuer("主動國泰動能高息"))
        assertEquals(Issuer.FUBON, IssuerDirectory.issuer("主動富邦動態入息"))
        assertEquals(Issuer.FHTRUST, IssuerDirectory.issuer("主動復華未來50"))
        assertEquals(Issuer.CTBC, IssuerDirectory.issuer("主動中信台灣收益"))
        assertEquals(Issuer.CAPITAL, IssuerDirectory.issuer(" 主動 群益科技創新 "))
        assertNull(IssuerDirectory.issuer("主動統一升級50"))
        assertNull(IssuerDirectory.issuer("主動"))
        assertNull(IssuerDirectory.issuer("統一主動元大"), "A company is not read out of the middle of a name")
    }

    @Test fun bondFunds() {
        assertEquals("債券型 ETF 沒有股票成分可顯示", IssuerDirectory.bondFund)
        assertTrue(IssuerDirectory.isBondFund("00679B", "指數股票型"))
        assertTrue(IssuerDirectory.isBondFund("00687B", null))
        assertTrue(IssuerDirectory.isBondFund("00937b", ""))
        assertTrue(IssuerDirectory.isBondFund("00999", "國外成分證券指數股票型基金(債券)"))
        assertTrue(IssuerDirectory.isBondFund("00998A", "主動式債券型"))
        assertFalse(IssuerDirectory.isBondFund("0050", "國內成分證券指數股票型基金"))
        assertFalse(IssuerDirectory.isBondFund("00878", null))
        assertFalse(IssuerDirectory.isBondFund("00631L", "槓桿型"))
        assertFalse(IssuerDirectory.isBondFund("00632R", "反向型"))
        assertFalse(IssuerDirectory.isBondFund("00982A", "主動式"))
        assertFalse(IssuerDirectory.isBondFund("00635U", "期貨信託"))
        assertFalse(IssuerDirectory.isBondFund("00980T", "股債平衡型"), "A balanced fund's stock holdings can be shown")
    }

    @Test fun day() {
        assertEquals("2026-11-11", IssuerHoldings.day("20261111"))
        assertEquals("2026-11-11", IssuerHoldings.day("2026/11/11"))
        assertEquals("2026-01-05", IssuerHoldings.day("2026/1/5"))
        assertEquals("2026-11-11", IssuerHoldings.day(" 2026-11-11 "))
        assertNull(IssuerHoldings.day("115/11/11"))
        assertNull(IssuerHoldings.day("2026/13/01"))
        assertNull(IssuerHoldings.day("abc"))
        assertNull(IssuerHoldings.day(JsonNull))
        assertNull(IssuerHoldings.day(JsonPrimitive(20261111)), "Only a string is a date")
    }

    // Holdings from the captured responses

    @Test fun yuanta() {
        val s = IssuerHoldings.yuanta(fx("E_yuanta_PCF_Daily_0050.json"), "0050")
        assertSnapshot(s, Issuer.YUANTA, "0050", "2026-11-11", 3, Triple("2330", "台積電", 58.7))
        assertFalse(s.components.any { it.symbol == "TX" }, "FutureWeights rows are not holdings")
    }

    @Test fun cathay() {
        val s = IssuerHoldings.cathay(fx("E_cathay_GetETFDetailStockList_00878.json"), "00878", "2026-11-13")
        assertSnapshot(s, Issuer.CATHAY, "00878", "2026-11-13", 3, Triple("2891", "中信金", 11.26))
        assertEquals("2026-11-13", IssuerHoldings.cathay(fx("E_cathay_GetETFDetailStockList_00878.json"), "00878", "2026/11/13").date)
    }

    @Test fun capital() {
        assertSnapshot(IssuerHoldings.capital(fx("E_capital_buyback_00919.json"), "00919"), Issuer.CAPITAL, "00919", "2026-11-13", 3, Triple("2881", "富邦金", 16.1341))
    }

    @Test fun fhtrust() {
        val s = IssuerHoldings.fhtrust(fx("E_fhtrust_assets_00929.json"), "00929")
        assertSnapshot(s, Issuer.FHTRUST, "00929", "2026-11-11", 3, Triple("2357", "華碩電腦", 4.123))
        assertFalse(s.components.any { it.symbol.startsWith("WTX") }, "The 期貨 row is dropped")
    }

    @Test fun ctbc() {
        assertSnapshot(IssuerHoldings.ctbc(fx("E_ctbc_ETFHoldingWeight_00934.json"), "00934"), Issuer.CTBC, "00934", "2026-11-13", 3, Triple("3293", "鈊象電子", 8.10))
    }

    @Test fun fubon() {
        val html = fx("E_fubon_Assets_006208_excerpt.html").decodeToString()
        val s = IssuerHoldings.fubon(html, "006208")
        assertSnapshot(s, Issuer.FUBON, "006208", "2026-11-13", 2, Triple("2330", "台積電", 58.4473))
        assertTrue(s.components.all { it.weight > 0 && it.weight <= 100 })
        // A later table (futures) is not read as stock rows, and a 合計 line is not a holding.
        val more = html.replace("</tbody></table>", "<tr><td colspan=\"4\">合計</td><td>64.6076</td></tr></tbody></table>") +
            "<table><tr><td>期貨代碼</td><td>期貨名稱</td><td>口數</td><td>金額</td><td>權重(%)</td></tr>" +
            "<tr><td>TX</td><td>臺股期貨</td><td>10</td><td>1,000</td><td>0.5</td></tr></table>"
        assertEquals(listOf("2330", "2454"), IssuerHoldings.fubon(more, "006208").components.map { it.symbol })
    }

    /** A footer row with as many cells as the header (合計 where the code belongs) is not a holding either. */
    @Test fun fubonSkipsRowsWithoutACode() {
        val head = "資料日期：2026/11/13<table><tr><td>股票代碼</td><td>股票名稱</td><td>股數</td><td>金額</td><td>權重(%)</td></tr>"
        val rows = "<tr><td>2330</td><td>台積電</td><td>1</td><td>2</td><td>58.4473</td></tr>" +
            "<tr><td>00679B</td><td>元大美債20年</td><td>1</td><td>2</td><td>1.5</td></tr>" +
            "<tr><td>AAPL US</td><td>Apple</td><td>1</td><td>2</td><td>3.25</td></tr>" +
            "<tr><td>BRK.B</td><td>Berkshire</td><td>1</td><td>2</td><td>1.25</td></tr>"
        val footer = "<tr><td>合計</td><td></td><td>4</td><td>8</td><td>64.4473</td></tr>" +
            "<tr><td>－</td><td>現金</td><td></td><td>9</td><td>0.5</td></tr></table>"
        val s = IssuerHoldings.fubon(head + rows + footer, "006208")
        assertEquals(listOf("2330", "00679B", "AAPL US", "BRK.B"), s.components.map { it.symbol })
        assertEquals(64.4473, s.totalWeight, 1e-9)
        fails { IssuerHoldings.fubon(head + footer, "006208") }
    }

    // Hardening

    @Test fun emptyHoldingsThrow() {
        fails { IssuerHoldings.yuanta(json("""{"PCF":{"markcd":"0050","trandate":"20261111"},"FundWeights":{"StockWeights":[]}}"""), "0050") }
        for (body in listOf("{}", "[]", "<html>維護中</html>", "")) {
            val data = json(body)
            fails { IssuerHoldings.yuanta(data, "0050") }
            fails { IssuerHoldings.cathay(data, "00878", "2026-11-13") }
            fails { IssuerHoldings.fubon(body, "006208") }
            fails { IssuerHoldings.capital(data, "00919") }
            fails { IssuerHoldings.fhtrust(data, "00929") }
            fails { IssuerHoldings.ctbc(data, "00934") }
        }
    }

    @Test fun errorBodiesThrow() {
        fails { IssuerHoldings.cathay(json("""{"result":null,"returnCode":"9999","success":false,"returnMessage":"查無資料"}"""), "00878", "2026-11-13") }
        fails { IssuerHoldings.capital(json("""{"code":500,"data":null,"message":"系統忙碌"}"""), "00919") }
        fails { IssuerHoldings.ctbc(json("""{"ResultCode":1,"ResultMsg":"查無資料","Data":null}"""), "00934") }
        fails { IssuerHoldings.fhtrust(json("""{"result":[],"status":0}"""), "00929") }
    }

    @Test fun reshapedRowsThrow() {
        fails { IssuerHoldings.cathay(json("""{"result":[{"code":"2891","title":"中信金","ratio":"11.26"}],"success":true}"""), "00878", "2026-11-13") }
        fails {
            IssuerHoldings.cathay(json("""{"result":[{"stockCode":"2891","stockName":"中信金","weights":"11.26"},{"stockCode":"2382","stockName":"廣達","weights":"--"}],"success":true}"""), "00878", "2026-11-13")
        }
        val ok = """{"result":[{"stockCode":"2891","stockName":"中信金","weights":"11.26"}],"success":true}"""
        fails { IssuerHoldings.cathay(json(ok), "00878", "") }
        fails { IssuerHoldings.cathay(json(ok), "00878", "2999-01-01") }
        fails { IssuerHoldings.yuanta(json("""{"PCF":{"markcd":"0050"},"FundWeights":{"StockWeights":[{"code":"2330","name":"台積電","weights":58.7}]}}"""), "0050") }
        fails {
            IssuerHoldings.cathay(json("""{"result":[{"stockCode":"2891","stockName":"中信金","weights":"80"},{"stockCode":"2382","stockName":"廣達","weights":"80"}],"success":true}"""), "00878", "2026-11-13")
        }
        fails { IssuerHoldings.fubon("<p>資料日期：2026/11/13</p><table><tr><td>項目</td><td>金額</td></tr></table>", "006208") }
        val table = "<table><tr><td>股票代碼</td><td>股票名稱</td><td>股數</td><td>金額</td><td>權重(%)</td></tr>" +
            "<tr><td>2330</td><td>台積電</td><td>1</td><td>2</td><td>58.4473</td></tr></table>"
        fails { IssuerHoldings.fubon(table, "006208") }
        assertEquals(1, IssuerHoldings.fubon("資料日期：2026/11/13$table", "006208").components.size)
    }

    @Test fun wrongFundThrows() {
        fails { IssuerHoldings.yuanta(fx("E_yuanta_PCF_Daily_0050.json"), "0056") }
        fails { IssuerHoldings.fhtrust(fx("E_fhtrust_assets_00929.json"), "00927") }
        fails { IssuerHoldings.ctbc(fx("E_ctbc_ETFHoldingWeight_00934.json"), "00882") }
    }

    @Test fun rowsAreCleaned() {
        val body = json(
            """{"result":[
              {"stockCode":" 2891 ","stockName":" 中信金 ","weights":"1.5"},
              {"stockCode":"2382","stockName":"廣達","weights":"8.01%"},
              {"stockCode":"2891","stockName":"中信金","weights":"2.25"},
              {"stockCode":"","stockName":"現金","weights":"3.34"},
              {"stockCode":"2882","stockName":"","weights":7}
            ],"success":true}""",
        )
        val s = IssuerHoldings.cathay(body, "00878", "2026-11-13")
        assertEquals(listOf("2891", "2382", "2882"), s.components.map { it.symbol })
        assertEquals("中信金", s.components[0].name)
        assertEquals(3.75, s.components[0].weight, 1e-9)
        assertEquals(8.01, s.components[1].weight, 1e-9)
        assertNull(s.components[2].name)
        assertEquals(7.0, s.components[2].weight, 1e-9)
    }

    // Fund-code lookups

    @Test fun capitalFundNo() {
        val data = fx("E_capital_items_sample.json")
        assertEquals("195", IssuerHoldings.capitalFundNo(data, "00919"))
        assertEquals("399", IssuerHoldings.capitalFundNo(data, "00982A"))
        assertNull(IssuerHoldings.capitalFundNo(data, "0050"))
        assertNull(IssuerHoldings.capitalFundNo(json("{}"), "00919"))
        assertNull(IssuerHoldings.capitalFundNo(json("oops"), "00919"))
    }

    @Test fun ctbcFID() {
        val data = fx("E_ctbc_ETFList_sample.json")
        assertEquals("E0024", IssuerHoldings.ctbcFID(data, "00934"))
        assertEquals("E0014", IssuerHoldings.ctbcFID(data, "00882"))
        assertNull(IssuerHoldings.ctbcFID(data, "0050"))
        assertNull(IssuerHoldings.ctbcFID(json("{}"), "00934"))
    }

    @Test fun cathayFundCode() {
        val data = fx("E_cathay_GetETFList_00878.json")
        assertEquals("CN", IssuerHoldings.cathayFundCode(data, "00878"))
        assertNull(IssuerHoldings.cathayFundCode(data, "0050"))
        val many = json("""{"totalCount":3,"result":[{"fundCode":"EA","stockCode":"00400A"},{"fundCode":"CN","stockCode":"00878"},{"fundCode":" ","stockCode":"00881"}],"returnCode":"2000","success":true}""")
        assertEquals("CN", IssuerHoldings.cathayFundCode(many, "00878"))
        assertEquals("EA", IssuerHoldings.cathayFundCode(many, "00400a"))
        assertNull(IssuerHoldings.cathayFundCode(many, "00881"))
        assertNull(IssuerHoldings.cathayFundCode(many, "0087"))
        assertNull(IssuerHoldings.cathayFundCode(json("""{"totalCount":0,"totalPage":0,"result":[],"returnCode":"2000","success":true}"""), "00878"))
        assertNull(IssuerHoldings.cathayFundCode(json("{}"), "00878"))
        assertNull(IssuerHoldings.cathayFundCode(json("oops"), "00878"))
    }

    @Test fun cathayAssetsDate() {
        val real = json("""{"result":{"preDate":"2026/11/13","fundNav":"664,848,873,726","fundOutstandingShares":"19,840,290,000","fundPerNav":"33.51"},"returnCode":"2000","success":true,"returnMessage":"成功"}""")
        assertEquals("2026-11-13", IssuerHoldings.cathayAssetsDate(real))
        assertEquals("2026-11-13", IssuerHoldings.cathayAssetsDate(json("""{"result":{"preDate":"2026-11-13T00:00:00"}}""")))
        assertNull(IssuerHoldings.cathayAssetsDate(json("""{"result":{"preDate":""}}""")))
        assertNull(IssuerHoldings.cathayAssetsDate(json("""{"result":null,"returnCode":"9999","success":false}""")))
        assertNull(IssuerHoldings.cathayAssetsDate(json("oops")))
    }

    @Test fun fhtrustFundID() {
        val html = fx("E_fhtrust_etf_list_excerpt.html").decodeToString()
        assertEquals("ETF21", IssuerHoldings.fhtrustFundID(html, "00929"))
        assertEquals("ETF23", IssuerHoldings.fhtrustFundID(html, "00991A"))
        assertEquals("ETF08", IssuerHoldings.fhtrustFundID(html, "00731"))
        assertNull(IssuerHoldings.fhtrustFundID(html, "0092"))
        assertNull(IssuerHoldings.fhtrustFundID(html, "0050"))
        assertNull(IssuerHoldings.fhtrustFundID(html, "2026"), "A date or a price in another cell is not a code")
        assertEquals("ETF21", IssuerHoldings.fhtrustFundID("<tr><td>00929</td><td><a href=\"/ETF/etf_detail/ETF21\">復華台灣科技優息</a></td></tr>", "00929"))
        val bare = "<table><tr><td>00929</td><td>復華台灣科技優息</td></tr>" +
            "<tr><td>00731</td><td><a href=\"/ETF/etf_detail/ETF08\">復華富時高息低波</a></td></tr></table>"
        assertNull(IssuerHoldings.fhtrustFundID(bare, "00929"), "The next row's id is not borrowed")
        assertEquals("ETF08", IssuerHoldings.fhtrustFundID(bare, "00731"))
        assertNull(IssuerHoldings.fhtrustFundID("", "00929"))
    }

    @Test fun ctbcToken() {
        assertEquals("aB+/c9==", IssuerHoldings.ctbcToken(json("""{"ResultCode":0,"ResultMsg":"","Data":{"token":" aB+/c9== "}}""")))
        assertNull(IssuerHoldings.ctbcToken(json("""{"ResultCode":0,"Data":{"token":""}}""")))
        assertNull(IssuerHoldings.ctbcToken(json("""{"ResultCode":1,"Data":null}""")))
        assertNull(IssuerHoldings.ctbcToken(json("<html>")))
    }

    /** NSRegularExpression's `\s` is Unicode-aware: a full-width space between 資料日期 and the colon still matches. */
    @Test fun fubonDateAllowsUnicodeSpaces() {
        val table = "<table><tr><td>股票代碼</td><td>股票名稱</td><td>權重(%)</td></tr><tr><td>2330</td><td>台積電</td><td>58.4</td></tr></table>"
        assertEquals("2026-11-13", IssuerHoldings.fubon("資料日期　： 2026/11/13$table", "006208").date)
    }
}
