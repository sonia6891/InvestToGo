import Foundation

/// The 口袋會員 features: each member screen is wrapped in `MemberLock` with its feature, which supplies the lock card's
/// title and pitch.
enum MemberFeature: String, CaseIterable, Codable {
    case overlap, activeTracking, scenarios, goalPlanner, report, backtest, priceAlerts

    var title: String {
        switch self {
        case .overlap: return "重疊成分"
        case .activeTracking: return "主動式追蹤"
        case .scenarios: return "多情境試算"
        case .goalPlanner: return "存錢目標反推"
        case .report: return "口袋月報年報"
        case .backtest: return "回測"
        case .priceAlerts: return "到價提醒"
        }
    }

    var pitch: String {
        switch self {
        case .overlap: return "看你持有的 ETF 重壓了哪些同樣的股票"
        case .activeTracking: return "追蹤主動式 ETF 每天買了什麼、賣了什麼"
        case .scenarios: return "樂觀、持平、悲觀三種情境一次試算"
        case .goalPlanner: return "告訴我們目標，反推每月要存多少"
        case .report: return "每月與每年自動整理成一份報告"
        case .backtest: return "用過去的價格回頭驗證你的買法"
        case .priceAlerts: return "設定價格，到了就通知你"
        }
    }
}
