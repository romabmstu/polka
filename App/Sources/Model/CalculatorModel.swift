import Foundation
import Observation
import OSLog
import PolkaCore
import PolkaSystem

@MainActor
@Observable
final class CalculatorModel {
    var expression = ""
    var amountText = "100"
    var baseCurrency: String

    private(set) var rates: ExchangeRates?
    private(set) var isRefreshing = false
    private(set) var ratesError: String?

    @ObservationIgnored private let client: RatesClient?
    @ObservationIgnored private let log = Logger(subsystem: "Polka", category: "rates")

    init(defaultCurrency: String) {
        baseCurrency = defaultCurrency
        let cache = try? LibraryStore.defaultFileURL().deletingLastPathComponent().appending(path: "rates.json")
        client = cache.map { RatesClient(cacheURL: $0) }
    }

    // MARK: Calculator

    var result: Decimal? {
        try? Arithmetic.evaluate(expression)
    }

    var formattedResult: String? {
        result.map { $0.formatted(.number.precision(.fractionLength(0...8))) }
    }

    // MARK: Currency

    var amount: Decimal? {
        if let value = try? Arithmetic.evaluate(amountText) { return value }
        return nil
    }

    func converted(to code: String) -> Decimal? {
        guard let amount, let rates else { return nil }
        return rates.convert(amount, from: baseCurrency, to: code)
    }

    func loadCachedRates() async {
        guard rates == nil, let client else { return }
        rates = await client.cached()
    }

    func refreshRatesIfNeeded(enabled: Bool) async {
        guard enabled else { return }
        await loadCachedRates()
        if rates?.isStale() ?? true { await refreshRates() }
    }

    func refreshRates() async {
        guard let client, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            rates = try await client.refresh()
            ratesError = nil
        } catch {
            ratesError = String(localized: "Couldn’t update rates. Showing the last saved ones.")
            log.error("Rates refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func symbol(for code: String) -> String {
        let locale = Locale(identifier: Locale.identifier(fromComponents: [NSLocale.Key.currencyCode.rawValue: code]))
        return locale.currencySymbol ?? code
    }
}
