package com.sonia.etftogo

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.sonia.etftogo.ui.AddHoldingScreen
import com.sonia.etftogo.ui.EtfTheme
import com.sonia.etftogo.ui.LobbyScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            EtfTheme {
                val model: AppModel = viewModel()
                val portfolio by model.portfolio.collectAsStateWithLifecycle()
                var adding by rememberSaveable { mutableStateOf(false) }
                if (adding) {
                    BackHandler { adding = false }
                    AddHoldingScreen(
                        funds = model.funds,
                        onSave = { holding -> model.addHolding(holding).also { if (it == null) adding = false } },
                        onCancel = { adding = false },
                    )
                } else {
                    LobbyScreen(portfolio = portfolio, readFailure = model.readFailure, onAddHolding = { adding = true })
                }
            }
        }
    }
}
