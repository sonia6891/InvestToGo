import Foundation

// Number and date text shared by screens and the logic that builds labels.
func money(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0))) }
func decimal(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...2))) }
func priceText(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2))) }
func signed(_ value: Double, _ format: (Double) -> String = money) -> String { (value > 0 ? "+" : (value < 0 ? "-" : "")) + format(abs(value)) }
func percentText(_ value: Double) -> String { signed(value, decimal) + "%" }
func shown(_ text: String, hidden: Bool) -> String { hidden ? "＊＊＊＊" : text }
func weekdayText(_ date: Date) -> String { ["週日", "週一", "週二", "週三", "週四", "週五", "週六"][Calendar.current.component(.weekday, from: date) - 1] }
func ymdText(_ date: Date) -> String { let c = Calendar.current.dateComponents([.year, .month, .day], from: date); return String(format: "%04d/%02d/%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0) }
/// Large totals in 萬 so they fit inside a donut.
func wanText(_ value: Double) -> String { abs(value) >= 1_000_000 ? "\(decimal((value / 1000).rounded() / 10))萬" : money(value) }
func monthDay(_ date: Date) -> String { "\(Calendar.current.component(.month, from: date))/\(Calendar.current.component(.day, from: date))" }
