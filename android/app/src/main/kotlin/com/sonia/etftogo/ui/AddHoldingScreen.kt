package com.sonia.etftogo.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sonia.etftogo.core.models.Fund
import com.sonia.etftogo.core.models.Holding
import java.time.Instant

/** 新增持有 (iPhone `HoldingEditor` for a new holding). The purchase date is today until A3 adds the date picker. */
@Composable
fun AddHoldingScreen(funds: List<Fund>, onSave: (Holding) -> String?, onCancel: () -> Unit) {
    var symbol by rememberSaveable { mutableStateOf("") }
    var name by rememberSaveable { mutableStateOf("") }
    var shares by rememberSaveable { mutableStateOf("") }
    var total by rememberSaveable { mutableStateOf("") }
    var broker by rememberSaveable { mutableStateOf("") }
    var error by rememberSaveable { mutableStateOf<String?>(null) }
    val form = HoldingForm(symbol, name, shares, total, broker)
    val query = symbol.trim().uppercase()
    val matches = if (query.isEmpty() || funds.any { it.id == query }) emptyList()
        else funds.filter { it.id.startsWith(query) || it.name.contains(symbol.trim()) }.take(6)

    Column(
        Modifier.fillMaxSize().background(Palette.background).safeDrawingPadding().imePadding()
            .verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("新增持有", color = Palette.text, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        OutlinedTextField(
            value = symbol,
            onValueChange = { value ->
                symbol = value
                funds.firstOrNull { it.id == value.trim().uppercase() }?.let { name = it.name }
            },
            label = { Text("搜尋 ETF 代號、名稱") },
            placeholder = { Text("例如 0050 或 00878") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters),
            modifier = Modifier.fillMaxWidth().testTag("holding-symbol"),
        )
        matches.forEach { fund ->
            Text(
                "${fund.id}  ${fund.name}",
                color = Palette.text,
                modifier = Modifier.fillMaxWidth().background(Palette.card, RoundedCornerShape(10.dp))
                    .clickable { symbol = fund.id; name = fund.name }.padding(12.dp).testTag("holding-match-${fund.id}"),
            )
        }
        OutlinedTextField(
            value = name, onValueChange = { name = it }, label = { Text("名稱（清單沒有時填寫）") }, singleLine = true,
            modifier = Modifier.fillMaxWidth().testTag("holding-name"),
        )
        OutlinedTextField(
            value = shares, onValueChange = { shares = it }, label = { Text("持有股數") }, placeholder = { Text("1,000 股 = 1 張") },
            suffix = { Text("股") }, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier.fillMaxWidth().testTag("holding-shares"),
        )
        OutlinedTextField(
            value = total, onValueChange = { total = it }, label = { Text("總成本（含手續費）") }, placeholder = { Text("實際付出金額") },
            suffix = { Text("元") }, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            modifier = Modifier.fillMaxWidth().testTag("holding-cost"),
        )
        OutlinedTextField(
            value = broker, onValueChange = { broker = it }, label = { Text("券商（選填）") }, singleLine = true,
            modifier = Modifier.fillMaxWidth().testTag("holding-broker"),
        )
        form.averageText?.let { Text(it, color = Palette.muted, fontSize = 13.sp) }
        error?.let { Text(it, color = Palette.gold, fontSize = 13.sp, modifier = Modifier.testTag("holding-error")) }
        Spacer(Modifier.height(4.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Button(
                onClick = onCancel, modifier = Modifier.weight(1f).height(50.dp), shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.card, contentColor = Palette.text),
            ) { Text("取消", fontWeight = FontWeight.Bold) }
            Button(
                onClick = {
                    error = when (val result = form.build(funds, Instant.now())) {
                        is HoldingForm.Result.Error -> result.text
                        is HoldingForm.Result.Ok -> onSave(result.holding)
                    }
                },
                modifier = Modifier.weight(1f).height(50.dp).testTag("save-holding"), shape = RoundedCornerShape(14.dp),
            ) { Text("儲存", fontWeight = FontWeight.Bold) }
        }
        Text("輸入 1,000 股代表 1 張。總成本請填實際付出的台幣金額（含手續費），會換算成平均成本。", color = Palette.muted, fontSize = 12.sp)
    }
}
