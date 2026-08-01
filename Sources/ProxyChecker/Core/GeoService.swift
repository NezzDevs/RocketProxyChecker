import Foundation

struct GeoInfo: Codable, Sendable, Hashable {
    var country: String?
    var countryCode: String?
    var regionName: String?
    var isp: String?
    var storedAt: Date = Date()

    var isEmpty: Bool {
        country == nil && countryCode == nil && regionName == nil && isp == nil
    }
}

private struct BatchEntry: Decodable {
    var status: String?
    var message: String?
    var country: String?
    var countryCode: String?
    var regionName: String?
    var isp: String?
    var query: String?
}

actor GeoService {

    static let shared = GeoService()

    private static let endpoint =
        "http://ip-api.com/batch?fields=status,message,country,countryCode,regionName,isp,query"
    private static let batchSize = 100
    private static let cacheLifetime: TimeInterval = 30 * 24 * 60 * 60

    private var cache: [String: GeoInfo] = [:]
    private var dnsCache: [String: String] = [:]
    private var loadedCache = false

    private var remaining: Int?
    private var resetAt: Date?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpAdditionalHeaders = ["Content-Type": "application/json"]
        return URLSession(configuration: config)
    }()

    func lookup(ips: [String],
                onProgress: (@Sendable (Int, Int) -> Void)? = nil) async -> [String: GeoInfo] {
        loadCacheIfNeeded()

        let unique = Array(Set(ips.filter { !$0.isEmpty }))
        var results: [String: GeoInfo] = [:]
        var pending: [String] = []

        for ip in unique {
            if let cached = cache[ip], Date().timeIntervalSince(cached.storedAt) < Self.cacheLifetime {
                results[ip] = cached
            } else {
                pending.append(ip)
            }
        }

        onProgress?(results.count, unique.count)
        guard !pending.isEmpty else { return results }

        for chunk in stride(from: 0, to: pending.count, by: Self.batchSize).map({
            Array(pending[$0..<min($0 + Self.batchSize, pending.count)])
        }) {
            if Task.isCancelled { break }
            await waitForCapacity()

            let fetched = await fetchBatch(chunk)
            for (ip, info) in fetched {
                cache[ip] = info
                results[ip] = info
            }
            onProgress?(results.count, unique.count)
        }

        saveCache()
        return results
    }

    func resolveHost(_ host: String) -> String? {
        if isIPLiteral(host) { return host }
        if let cached = dnsCache[host] { return cached }

        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM

        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &info) == 0, let first = info else { return nil }
        defer { freeaddrinfo(info) }

        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(first.pointee.ai_addr,
                          first.pointee.ai_addrlen,
                          &buffer, socklen_t(buffer.count),
                          nil, 0,
                          NI_NUMERICHOST) == 0 else { return nil }

        let ip = String(cString: buffer)
        dnsCache[host] = ip
        return ip
    }

    func clearCache() {
        cache.removeAll()
        dnsCache.removeAll()
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    var cachedCount: Int {
        loadCacheIfNeeded()
        return cache.count
    }

    private func waitForCapacity() async {
        guard let remaining, remaining <= 0, let resetAt else { return }
        let wait = resetAt.timeIntervalSinceNow
        guard wait > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64((wait + 1) * 1_000_000_000))
        self.remaining = nil
        self.resetAt = nil
    }

    private func recordHeaders(_ response: HTTPURLResponse) {
        if let value = response.value(forHTTPHeaderField: "X-Rl"), let rl = Int(value) {
            remaining = rl
        }
        if let value = response.value(forHTTPHeaderField: "X-Ttl"), let ttl = Double(value) {
            resetAt = Date().addingTimeInterval(ttl)
        }
    }

    private func fetchBatch(_ ips: [String], isRetry: Bool = false) async -> [String: GeoInfo] {
        guard let url = URL(string: Self.endpoint),
              let body = try? JSONSerialization.data(withJSONObject: ips) else { return [:] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await session.data(for: request)

            if let http = response as? HTTPURLResponse {
                recordHeaders(http)

                if http.statusCode == 429 {
                    guard !isRetry else { return [:] }
                    let wait = resetAt?.timeIntervalSinceNow ?? 60
                    try? await Task.sleep(nanoseconds: UInt64((max(wait, 5) + 1) * 1_000_000_000))
                    return await fetchBatch(ips, isRetry: true)
                }
                guard http.statusCode == 200 else { return [:] }
            }

            let entries = try JSONDecoder().decode([BatchEntry].self, from: data)
            var out: [String: GeoInfo] = [:]

            for (index, entry) in entries.enumerated() {
                let ip = entry.query ?? (index < ips.count ? ips[index] : nil)
                guard let ip else { continue }
                guard entry.status != "fail" else { continue }

                let info = GeoInfo(country: entry.country,
                                   countryCode: entry.countryCode,
                                   regionName: entry.regionName,
                                   isp: entry.isp)
                if !info.isEmpty { out[ip] = info }
            }
            return out

        } catch {
            return [:]
        }
    }

    private static var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = base.appendingPathComponent("ProxyChecker", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("geo-cache.json")
    }

    private func loadCacheIfNeeded() {
        guard !loadedCache else { return }
        loadedCache = true
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let decoded = try? JSONDecoder().decode([String: GeoInfo].self, from: data) else { return }
        let cutoff = Date().addingTimeInterval(-Self.cacheLifetime)
        cache = decoded.filter { $0.value.storedAt > cutoff }
    }

    private func saveCache() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }

    private nonisolated func isIPLiteral(_ host: String) -> Bool {
        var v4 = in_addr()
        if inet_pton(AF_INET, host, &v4) == 1 { return true }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, host, &v6) == 1 { return true }
        return false
    }
}
