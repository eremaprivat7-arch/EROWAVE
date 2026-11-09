import Foundation

actor CatalogHTTP {
    static let shared = CatalogHTTP()
    private var next = [String: Date]()
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        self.session = URLSession(configuration: config)
    }
    func get<T: Decodable>(_ base: String, _ items: [URLQueryItem], as: T.Type) async throws -> T {
        guard var components = URLComponents(string: base), let host = components.host else { throw URLError(.badURL) }
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("EROWAVE/1.0 (https://t.me/clovissff)", forHTTPHeaderField: "User-Agent")
        for attempt in 0..<3 {
            while let time = next[host], time > Date() {
                guard time.timeIntervalSinceNow <= 12 else { throw URLError(.resourceUnavailable) }
                try await Task.sleep(for: .seconds(max(0, time.timeIntervalSinceNow)))
            }
            try Task.checkCancellation()
            let interval = host == "musicbrainz.org" ? 1.1 : ["itunes.apple.com","www.loc.gov"].contains(host) ? 3.2 : 0.3
            next[host] = Date().addingTimeInterval(interval)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 200 { return try JSONDecoder().decode(T.self, from: data) }
            guard [429, 502, 503, 504].contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let delay = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? (host == "www.loc.gov" && http.statusCode == 429 ? 3600 : pow(2, Double(attempt)))
            next[host] = max(next[host] ?? Date(), Date().addingTimeInterval(delay))
            if delay > 12 { throw URLError(.resourceUnavailable) }
        }
        throw URLError(.resourceUnavailable)
    }
}

func queryItems(_ values: [String: String]) -> [URLQueryItem] {
    values.map { URLQueryItem(name: $0.key, value: $0.value) }
}
