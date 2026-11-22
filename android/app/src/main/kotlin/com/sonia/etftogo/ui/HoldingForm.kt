package com.sonia.etftogo.ui

import com.sonia.etftogo.core.models.Fund
import com.sonia.etftogo.core.models.Holding
import com.sonia.etftogo.core.models.Strategy
import com.sonia.etftogo.core.support.DataChecks
import com.sonia.etftogo.core.support.priceText
import java.time.Instant

/** The 新增持有 fields as typed; [build] is iPhone `HoldingEditor.save()`'s checks for a new holding. */
data class HoldingForm(val symbol: String, val name: String, val shares: String, val total: String, val broker: String) {
    sealed interface Result {
        data class Ok(val holding: Holding) : Result
        data class Error(val text: String) : Result
    }

    val averageText: String? get() {
        val s = number(shares) ?: return null
        val t = number(total) ?: return null
        return if (s > 0 && t > 0) "平均成本 ${priceText(t / s)} 元／股" else null
    }

    fun build(funds: List<Fund>, date: Instant): Result {
        val code = symbol.trim().uppercase()
        val s = number(shares) ?: 0.0
        val t = number(total) ?: -1.0
        val fund = funds.firstOrNull { it.id == code }
        if (!DataChecks.code(code)) return Result.Error("請輸入正確的 ETF 代號，例如 0050、00878。")
        if (fund == null) return Result.Error("目前只支援 ETF，請輸入 ETF 名單中的代號。")
        if (!(s > 0)) return Result.Error("持有股數須大於 0。")
        if (!(t >= 0)) return Result.Error("請填寫總成本（含手續費）。")
        val typed = name.trim()
        return Result.Ok(
            Holding(
                symbol = code,
                name = typed.ifEmpty { fund.name },
                shares = s,
                unitCost = t / s,
                broker = broker.trim(),
                strategy = fund.strategy,
                purchaseDate = date,
            )
        )
    }

    private fun number(text: String): Double? = text.replace(",", "").trim().toDoubleOrNull()
}
