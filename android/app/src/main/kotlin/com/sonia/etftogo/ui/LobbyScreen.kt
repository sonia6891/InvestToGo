package com.sonia.etftogo.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sonia.etftogo.core.game.GameRules
import com.sonia.etftogo.core.game.GameState
import com.sonia.etftogo.core.models.Portfolio
import com.sonia.etftogo.core.support.decimal
import com.sonia.etftogo.core.support.money
import java.time.Instant

@Composable
fun LobbyScreen(portfolio: Portfolio, readFailure: Boolean, onAddHolding: () -> Unit, now: Instant = Instant.now()) {
    val game = portfolio.game ?: GameState()
    val hero = LobbyHero.of(game, now)
    val level = GameRules.level(game.xp)
    val progress = GameRules.progress(game.xp)
    Column(
        Modifier.fillMaxSize().background(Palette.background).safeDrawingPadding().padding(horizontal = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(Modifier.fillMaxWidth().padding(top = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("Lv $level", color = Palette.gold, fontWeight = FontWeight.Bold, fontSize = 18.sp)
            LinearProgressIndicator(
                progress = { if (progress.needed > 0) progress.into.toFloat() / progress.needed else 0f },
                modifier = Modifier.weight(1f).padding(horizontal = 12.dp).testTag("lobby-xp"),
                color = Palette.gold,
                trackColor = Palette.card,
            )
            Text("金幣 ${game.coins}", color = Palette.text, fontSize = 15.sp)
        }

        Spacer(Modifier.height(36.dp))
        Text(hero.tag, color = Palette.muted, fontSize = 15.sp)
        Text(
            "${hero.value}",
            color = Palette.gold,
            fontSize = 120.sp,
            fontWeight = FontWeight.Black,
            modifier = Modifier.semantics { contentDescription = hero.label }.testTag("lobby-hero"),
        )
        Text(hero.caption, color = Palette.text, fontSize = 18.sp)
        hero.record?.let { Text(it, color = Palette.muted, fontSize = 13.sp) }

        Spacer(Modifier.height(28.dp))
        if (readFailure) {
            Text("存檔無法讀取，已保留原檔，這次不會覆蓋。", color = Palette.gold, fontSize = 13.sp)
            Spacer(Modifier.height(8.dp))
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text("口袋", color = Palette.text, fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Text("投入成本 NT$${money(portfolio.cost)}", color = Palette.muted, fontSize = 14.sp)
        }
        Spacer(Modifier.height(8.dp))
        if (portfolio.holdings.isEmpty()) {
            Text("還沒有持有紀錄。", color = Palette.muted, modifier = Modifier.padding(vertical = 16.dp))
        }
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(portfolio.holdings, key = { it.id }) { holding ->
                Row(
                    Modifier.fillMaxWidth().background(Palette.card, RoundedCornerShape(12.dp)).padding(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("${holding.symbol}  ${holding.name}", color = Palette.text, fontWeight = FontWeight.SemiBold)
                        Text("${decimal(holding.shares)} 股 · 均價 ${decimal(holding.unitCost)}", color = Palette.muted, fontSize = 13.sp)
                    }
                    Text("NT$${money(holding.cost)}", color = Palette.text)
                }
            }
        }
        Button(
            onClick = onAddHolding,
            modifier = Modifier.fillMaxWidth().padding(vertical = 16.dp).height(52.dp).testTag("lobby-add-holding"),
            shape = RoundedCornerShape(14.dp),
        ) { Text("新增持有", fontSize = 17.sp, fontWeight = FontWeight.Bold) }
    }
}
