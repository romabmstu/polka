import Foundation
import PolkaCore

/// Downloads exchange rates from open.er-api.com and caches them on disk.
///
/// This is the only network request Polka makes, and only after the user turns
/// it on. The session is ephemeral: no cookies, no cache, no credentials.
public actor RatesClient {
    public static let endpoint = URL(string: "https://open.er-api.com/v6/latest/USD")!
    public static let attributionURL = URL(string: "https://www.exchangerate-api.com")!

    public enum Failure: Error, Equatable {
        case badResponse(Int)
        case tooLarge
    }

    private let session: URLSession
    private let cacheURL: URL
    private static let maximumResponseSize = 256 * 1024

    public init(cacheURL: URL) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        self.session = URLSession(configuration: configuration)
        self.cacheURL = cacheURL
    }

    public func cached() -> ExchangeRates? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ExchangeRates.self, from: data)
    }

    public func refresh() async throws -> ExchangeRates {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.badResponse(status) }
        guard data.count <= Self.maximumResponseSize else { throw Failure.tooLarge }

        let rates = try ExchangeRates.decodeOpenERAPI(data)
        try? store(rates)
        return rates
    }

    private func store(_ rates: ExchangeRates) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try encoder.encode(rates).write(to: cacheURL, options: .atomic)
    }
}
