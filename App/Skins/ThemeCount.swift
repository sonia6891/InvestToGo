import Foundation

/// How many 外觀主題 there are, in words. The 工具 tile and the 會員 page both say 「N套世界任你換」; building it from
/// `Skins.all.count` means the next theme cannot leave a stale number behind.
enum ThemeCount {
    private static let numerals = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

    /// 1…10 as 一…十; anything else falls back to Arabic digits (the phrase still reads, and a test notices).
    static func chinese(_ n: Int) -> String { numerals.indices.contains(n) && n > 0 ? numerals[n] : String(n) }

    static var count: Int { Skins.all.count }
    /// 「五套世界任你換」 today.
    static var phrase: String { "\(chinese(count))套世界任你換" }
}
