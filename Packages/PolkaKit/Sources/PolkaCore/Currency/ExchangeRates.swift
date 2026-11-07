import Foundation

/// A snapshot of rates relative to one base currency.
public struct ExchangeRates: Codable, Equatable, Sendable {
    public var base: String
    /// Units of each currency per one unit of `base`.
    public var rates: [String: Decimal]
    public var fetchedAt: Date
    public var publishedAt: Date?

    public init(base: String, rates: [String: Decimal], fetchedAt: Date = .now, publishedAt: Date? = nil) {
        self.base = base.uppercased()
        var rates = rates
        rates[self.base] = 1
        self.rates = rates
        self.fetchedAt = fetchedAt
        self.publishedAt = publishedAt
    }

    public func convert(_ amount: Decimal, from: String, to: String) -> Decimal? {
        guard
            let fromRate = rates[from.uppercased()], fromRate > 0,
            let toRate = rates[to.uppercased()]
        else { return nil }
        return amount / fromRate * toRate
    }

    public func isStale(now: Date = .now, maxAge: TimeInterval = 6 * 60 * 60) -> Bool {
        now.timeIntervalSince(fetchedAt) > maxAge
    }
}

extension ExchangeRates {
    /// Response of `https://open.er-api.com/v6/latest/<BASE>`.
    struct OpenERAPIResponse: Decodable {
        var result: String
        var baseCode: String
        var lastUpdate: TimeInterval?
        var rates: [String: Decimal]

        enum CodingKeys: String, CodingKey {
            case result, rates
            case baseCode = "base_code"
            case lastUpdate = "time_last_update_unix"
        }
    }

    public enum DecodingFailure: Error, Equatable {
        case providerError
        case implausibleRates
    }

    /// Decodes and sanity-checks the provider's answer; nothing from the network is
    /// trusted as-is.
    public static func decodeOpenERAPI(_ data: Data, now: Date = .now) throws -> ExchangeRates {
        let response = try JSONDecoder().decode(OpenERAPIResponse.self, from: data)
        guard response.result == "success" else { throw DecodingFailure.providerError }

        let currencyCode = /^[A-Z]{3}$/
        let rates = response.rates.filter { code, rate in
            code.wholeMatch(of: currencyCode) != nil && rate > 0 && rate < 1_000_000_000
        }
        guard rates.count >= 10, response.baseCode.wholeMatch(of: currencyCode) != nil else {
            throw DecodingFailure.implausibleRates
        }
        return ExchangeRates(
            base: response.baseCode,
            rates: rates,
            fetchedAt: now,
            publishedAt: response.lastUpdate.map(Date.init(timeIntervalSince1970:))
        )
    }
}
