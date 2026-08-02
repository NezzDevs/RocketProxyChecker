import Foundation

enum ProxyType: String, Codable, CaseIterable, Sendable, Identifiable {
    case http
    case https
    case socks4
    case socks5
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .http: return "HTTP"
        case .https: return "HTTPS"
        case .socks4: return "SOCKS4"
        case .socks5: return "SOCKS5"
        case .unknown: return "—"
        }
    }

    var scheme: String {
        switch self {
        case .http: return "http"
        case .https: return "https"
        case .socks4: return "socks4"
        case .socks5: return "socks5"
        case .unknown: return "http"
        }
    }

    static let detectionOrder: [ProxyType] = [.socks5, .http, .socks4]

    static func primary(of set: Set<ProxyType>) -> ProxyType? {
        detectionOrder.first { set.contains($0) }
    }

    static func label(for set: Set<ProxyType>) -> String {
        let ordered = detectionOrder.filter { set.contains($0) }
        guard !ordered.isEmpty else { return "—" }
        return ordered.map(\.label).joined(separator: " · ")
    }

    static func from(scheme: String) -> ProxyType? {
        switch scheme.lowercased() {
        case "http": return .http
        case "https", "ssl", "tls": return .https
        case "socks4", "socks4a": return .socks4
        case "socks5", "socks", "socks5h": return .socks5
        default: return nil
        }
    }
}

enum ProxyStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case notTested
    case checking
    case good
    case slow
    case timeout
    case failed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notTested: return "Not Tested"
        case .checking: return "Checking"
        case .good: return "Good"
        case .slow: return "Slow"
        case .timeout: return "Timeout"
        case .failed: return "Failed"
        }
    }
}

enum Anonymity: String, Codable, CaseIterable, Sendable, Identifiable {
    case elite
    case anonymous
    case transparent
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .elite: return "Elite"
        case .anonymous: return "Anonymous"
        case .transparent: return "Transparent"
        case .unknown: return "—"
        }
    }
}

struct ProxyRow: Identifiable, Sendable, Hashable {
    let id: UUID
    var host: String
    var port: Int
    var username: String?
    var password: String?

    var declaredType: ProxyType?

    var resolvedType: ProxyType

    var status: ProxyStatus
    var speedMs: Int?

    var statusCode: Int?
    var exitIP: String?
    var country: String?
    var countryCode: String?
    var state: String?
    var isp: String?
    var anonymity: Anonymity
    var error: String?
    var checkedAt: Date?

    init(host: String, port: Int, username: String? = nil, password: String? = nil, declaredType: ProxyType? = nil) {
        self.id = UUID()
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.declaredType = declaredType
        self.resolvedType = declaredType ?? .unknown
        self.supportedTypes = declaredType.map { [$0] } ?? []
        self.status = .notTested
        self.anonymity = .unknown
    }

    var needsAuth: Bool { username?.isEmpty == false }

    var endpoint: String { "\(host):\(port)" }

    func formatted(_ format: ExportFormat) -> String {
        let auth = needsAuth ? "\(username ?? ""):\(password ?? "")" : nil
        switch format {
        case .hostPort:
            return endpoint
        case .hostPortUserPass:
            if let auth { return "\(host):\(port):\(auth)" }
            return endpoint
        case .userPassAtHost:
            if let auth { return "\(auth)@\(host):\(port)" }
            return endpoint
        case .schemeURL:
            if let auth { return "\(resolvedType.scheme)://\(auth)@\(host):\(port)" }
            return "\(resolvedType.scheme)://\(host):\(port)"
        case .csv, .json:
            return endpoint
        }
    }
}

enum TypeMode: String, CaseIterable, Identifiable, Codable {
    case auto
    case http
    case https
    case socks4
    case socks5

    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Auto-detect"
        case .http: return "Force HTTP"
        case .https: return "Force HTTPS"
        case .socks4: return "Force SOCKS4"
        case .socks5: return "Force SOCKS5"
        }
    }
    var forcedType: ProxyType? {
        switch self {
        case .auto: return nil
        case .http: return .http
        case .https: return .https
        case .socks4: return .socks4
        case .socks5: return .socks5
        }
    }
}

enum GeoSource: String, CaseIterable, Identifiable, Codable {
    case proxyHost
    case exitIP

    var id: String { rawValue }

    var label: String {
        switch self {
        case .proxyHost: return "Proxy address (free)"
        case .exitIP: return "Exit IP (accurate for gateways)"
        }
    }

    var help: String {
        switch self {
        case .proxyHost:
            return "Resolves the proxy's own address locally. No requests through the proxy at all."
        case .exitIP:
            return "Asks each proxy what IP it exits from. Correct for rotating gateways, one extra request per proxy."
        }
    }
}

struct HTTPHeader: Codable, Sendable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var value: String = ""
    var enabled: Bool = true

    static let reserved: Set<String> = [
        "content-length", "connection", "host", "authorization",
        "proxy-authenticate", "proxy-authorization", "www-authenticate"
    ]

    var isReserved: Bool {
        Self.reserved.contains(name.trimmingCharacters(in: .whitespaces).lowercased())
    }

    var isUsable: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isReserved
    }
}

struct CheckSettings: Codable, Sendable, Equatable {

    static let supersededTargets: Set<String> = [
        "https://www.google.com/generate_204",
        "http://ip-api.com/json/"
    ]

    var threads: Int = 100
    var timeoutSeconds: Double = 10
    var slowThresholdMs: Int = 1500
    var targetURL: String = "https://www.google.com"
    var typeMode: TypeMode = .auto
    var lookupGeo: Bool = true
    var geoSource: GeoSource = .proxyHost
    var detectAnonymity: Bool = true
    var judgeURL: String = "http://azenv.net/"
    var retries: Int = 0
    var userAgent: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    var customHeaders: [HTTPHeader] = []

    var resolvedHeaders: [String: String] {
        var out: [String: String] = [:]
        for header in customHeaders where header.enabled && header.isUsable {
            out[header.name.trimmingCharacters(in: .whitespaces)] = header.value
        }
        return out
    }

    static let exitIPEndpoint = "http://ip-api.com/json/?fields=status,query"

    var targetHost: String { URL(string: targetURL)?.host ?? targetURL }

    var targetIsGeoEndpoint: Bool {
        (URL(string: targetURL)?.host ?? "").lowercased().contains("ip-api.com")
    }
}

enum ExportFormat: String, CaseIterable, Identifiable, Codable {
    case hostPort
    case hostPortUserPass
    case userPassAtHost
    case schemeURL
    case csv
    case json

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hostPort: return "host:port"
        case .hostPortUserPass: return "host:port:user:pass"
        case .userPassAtHost: return "user:pass@host:port"
        case .schemeURL: return "scheme://user:pass@host:port"
        case .csv: return "CSV (all fields)"
        case .json: return "JSON (all fields)"
        }
    }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .json: return "json"
        default: return "txt"
        }
    }
}

enum ExportGrouping: String, CaseIterable, Identifiable, Codable {
    case single
    case byType
    case byCountry
    case byState
    case byAnonymity
    case bySpeed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .single: return "One file"
        case .byType: return "One file per type"
        case .byCountry: return "One file per country"
        case .byState: return "One file per state"
        case .byAnonymity: return "One file per security type"
        case .bySpeed: return "One file per speed band"
        }
    }
}

struct ExportFilter: Codable, Equatable {
    var statuses: Set<String> = [ProxyStatus.good.rawValue]
    var types: Set<String> = []
    var countries: Set<String> = []
    var states: Set<String> = []
    var anonymities: Set<String> = []
    var maxSpeedMs: Int = 0

    func matches(_ row: ProxyRow) -> Bool {
        guard statuses.contains(row.status.rawValue) else { return false }
        if !types.isEmpty {
            let available = row.supportedTypes.isEmpty ? [row.resolvedType] : Array(row.supportedTypes)
            guard available.contains(where: { types.contains($0.rawValue) }) else { return false }
        }
        if !countries.isEmpty, !countries.contains(row.country ?? "Unknown") { return false }
        if !states.isEmpty, !states.contains(row.state ?? "Unknown") { return false }
        if !anonymities.isEmpty, !anonymities.contains(row.anonymity.rawValue) { return false }
        if maxSpeedMs > 0 {
            guard let ms = row.speedMs, ms <= maxSpeedMs else { return false }
        }
        return true
    }
}

enum SpeedBand: String, CaseIterable {
    case under250 = "0-250ms"
    case under500 = "250-500ms"
    case under1000 = "500-1000ms"
    case under3000 = "1000-3000ms"
    case over3000 = "3000ms+"
    case unknown = "unknown"

    static func band(for ms: Int?) -> SpeedBand {
        guard let ms else { return .unknown }
        switch ms {
        case ..<250: return .under250
        case ..<500: return .under500
        case ..<1000: return .under1000
        case ..<3000: return .under3000
        default: return .over3000
        }
    }
}
