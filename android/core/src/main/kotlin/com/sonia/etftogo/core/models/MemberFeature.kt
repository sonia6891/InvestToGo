package com.sonia.etftogo.core.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** The 口袋會員 features: each member screen is wrapped in a lock with its feature, which supplies the card's title and pitch. */
@Serializable
enum class MemberFeature(val title: String, val pitch: String) {
    @SerialName("overlap") OVERLAP("重疊成分", "看你持有的 ETF 重壓了哪些同樣的股票"),
    @SerialName("activeTracking") ACTIVE_TRACKING("主動式追蹤", "看主動式 ETF 新增、剔除了哪些持股，權重怎麼變"),
    @SerialName("scenarios") SCENARIOS("多情境試算", "保守、基準、樂觀與壓力測試，四種情境一次試算"),
    @SerialName("goalPlanner") GOAL_PLANNER("存錢目標反推", "設定目標金額與年數，算出每月要投多少"),
    @SerialName("report") REPORT("口袋月報／年報", "每月與每年自動整理成一份報告"),
    @SerialName("backtest") BACKTEST("回測", "看看過去這樣每月買，會變成多少"),
    @SerialName("priceAlerts") PRICE_ALERTS("到價提醒", "設定價格，到了就通知你"),
}
