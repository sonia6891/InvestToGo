package com.sonia.etftogo.data

import com.sonia.etftogo.core.game.GameState
import com.sonia.etftogo.core.game.logBuy
import com.sonia.etftogo.core.models.Holding
import com.sonia.etftogo.core.models.Portfolio
import com.sonia.etftogo.core.models.StoreError
import com.sonia.etftogo.core.models.TradeAction
import com.sonia.etftogo.core.support.AppDataError
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Instant

/**
 * The records file, as on iPhone (spec 7.3): `files/ETFToGo/portfolio.json`, written to a temporary file and renamed so
 * a crash never leaves half a file. A file that cannot be read is kept and never saved over.
 * A2 keeps the records only; the side files (.histories, .holdings, .alerts) arrive with the features that write them.
 */
class PortfolioStore(root: File) {
    private val file = File(root, "ETFToGo/portfolio.json")

    var data: Portfolio = Portfolio()
        private set

    /** True when a records file exists but could not be read; every save is refused until it is dealt with. */
    var readFailure: Boolean = false
        private set

    init {
        if (file.exists()) {
            try {
                data = Portfolio.decodeBackup(file.readBytes())
            } catch (_: Exception) {
                readFailure = true
            }
        }
    }

    /**
     * iPhone `PortfolioStore.save(_:logBuy:now:)`: a new holding is appended with its buy, and with [logBuy] a holding
     * with a purchase date is the user's buy, recording the DCA month in the same write. Edits log an adjustment.
     */
    fun save(holding: Holding, logBuy: Boolean = false, now: Instant = Instant.now()) {
        holding.validate()
        var next = data
        val i = next.holdings.indexOfFirst { it.id == holding.id }
        if (i >= 0) {
            val old = next.holdings[i]
            next = next.copy(holdings = next.holdings.toMutableList().also { it[i] = holding })
            if (old.symbol != holding.symbol || old.shares != holding.shares || old.unitCost != holding.unitCost || old.broker != holding.broker) {
                next = next.log(TradeAction.ADJUST, holding)
            }
        } else {
            next = next.copy(holdings = next.holdings + holding)
                .log(TradeAction.BUY, holding, date = holding.purchaseDate ?: now, amount = holding.cost)
            val bought = holding.purchaseDate
            if (logBuy && bought != null) next = next.copy(game = (next.game ?: GameState()).logBuy(bought, now).first)
        }
        commit(next)
    }

    private fun commit(next: Portfolio) {
        if (readFailure) throw StoreError.UnsupportedBackup
        val records = next.copy(alerts = null, histories = null, componentHistory = null)
        val encoded = records.encode()
        if (encoded.size > 5_000_000) throw AppDataError("紀錄超過 5 MB 上限，這次變更未儲存；現有資料未變更。")
        Portfolio.decodeBackup(encoded)
        file.parentFile.mkdirs()
        val temp = File(file.parentFile, file.name + ".tmp")
        temp.writeBytes(encoded)
        Files.move(temp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        data = next
    }
}
