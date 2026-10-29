import SafariServices
import SwiftUI

/// 看即時價: without the viewer's own Fugle key the app shows each trading day's close, so the stock and ETF pages
/// offer the live quote on Yahoo 股市 in an in-app Safari sheet. Hidden once a key is saved (prices then stream here).
struct LiveQuoteButton: View {
    @EnvironmentObject var store: PortfolioStore
    let symbol: String
    /// "TWSE" or "TPEx"; Yahoo marks OTC codes .TWO.
    let market: String?
    @State private var showing = false
    var body: some View {
        if !store.liveStatus.hasKey, DataChecks.code(symbol) {
            Button { showing = true } label: { Text("看即時價").font(.caption.bold()) }
                .accessibilityLabel("看即時價")
                .sheet(isPresented: $showing) { SafariSheet(url: Self.url(symbol, market: market)).ignoresSafeArea() }
        }
    }
    static func url(_ symbol: String, market: String?) -> URL {
        URL(string: "https://tw.stock.yahoo.com/quote/\(symbol)\(market == "TPEx" ? ".TWO" : ".TW")")!
    }
}

struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
