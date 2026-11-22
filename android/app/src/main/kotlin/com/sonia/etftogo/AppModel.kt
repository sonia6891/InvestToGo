package com.sonia.etftogo

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import com.sonia.etftogo.core.models.Fund
import com.sonia.etftogo.core.models.Holding
import com.sonia.etftogo.core.models.Portfolio
import com.sonia.etftogo.core.sources.CatalogSnapshot
import com.sonia.etftogo.data.PortfolioStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.Instant

/** The records and the ETF list the screens read; every change goes through [PortfolioStore] first. */
class AppModel(app: Application) : AndroidViewModel(app) {
    private val store = PortfolioStore(app.filesDir)
    private val _portfolio = MutableStateFlow(store.data)
    val portfolio: StateFlow<Portfolio> = _portfolio.asStateFlow()

    /** The bundled list until A3 adds the daily official refresh; the six well-known funds if it cannot be read. */
    val funds: List<Fund> = CatalogSnapshot.bundled()?.funds ?: Fund.starters

    val readFailure: Boolean get() = store.readFailure

    /** 新增持有's 儲存: the holding, its buy, and this month's DCA in one write. Returns the error text, or null. */
    fun addHolding(holding: Holding, now: Instant = Instant.now()): String? = try {
        store.save(holding, logBuy = true, now = now)
        _portfolio.value = store.data
        null
    } catch (error: Exception) {
        error.message ?: "無法儲存，請再試一次。"
    }
}
