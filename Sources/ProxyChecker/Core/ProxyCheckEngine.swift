import Foundation

struct CheckOutcome: Sendable {
    var status: ProxyStatus = .failed
    var speedMs: Int?
    var statusCode: Int?
    var type: ProxyType = .unknown
    var supportedTypes: Set<ProxyType> = []
    var exitIP: String?
    var country: String?
    var countryCode: String?
    var state: String?
    var isp: String?
    var anonymity: Anonymity = .unknown
    var error: String?
}

private final class ProxyAuthDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let credential: URLCredential?

    init(username: String?, password: String?) {
        if let username, !username.isEmpty {
            credential = URLCredential(user: username, password: password ?? "", persistence: .none)
        } else {
            credential = nil
        }
        super.init()
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod

        if method == NSURLAuthenticationMethodServerTrust {

            if let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
            return
        }

        guard let credential, challenge.previousFailureCount < 2 else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, credential)
    }
}

private struct ExitIPResponse: Decodable {
    var status: String?
    var query: String?
}

enum ProxyCheckEngine {

    private static func proxyDictionary(host: String,
                                        port: Int,
                                        type: ProxyType,
                                        username: String?,
                                        password: String?) -> [AnyHashable: Any] {
        switch type {
        case .socks4, .socks5:
            var dict: [AnyHashable: Any] = [
                kCFStreamPropertySOCKSProxyHost as String: host,
                kCFStreamPropertySOCKSProxyPort as String: port,
                kCFStreamPropertySOCKSVersion as String: type == .socks5
                    ? (kCFStreamSocketSOCKSVersion5 as String)
                    : (kCFStreamSocketSOCKSVersion4 as String)
            ]
            if let username, !username.isEmpty {
                dict[kCFStreamPropertySOCKSUser as String] = username
                dict[kCFStreamPropertySOCKSPassword as String] = password ?? ""
            }
            return dict

        case .http, .https, .unknown:
            return [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
                kCFNetworkProxiesHTTPSEnable as String: 1,
                kCFNetworkProxiesHTTPSProxy as String: host,
                kCFNetworkProxiesHTTPSPort as String: port
            ]
        }
    }

    private static func makeSession(row: ProxyRow,
                                    type: ProxyType,
                                    settings: CheckSettings) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = proxyDictionary(
            host: row.host, port: row.port, type: type,
            username: row.username, password: row.password
        )
        config.timeoutIntervalForRequest = settings.timeoutSeconds
        config.timeoutIntervalForResource = settings.timeoutSeconds
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpMaximumConnectionsPerHost = 2
        config.waitsForConnectivity = false
        config.allowsCellularAccess = true

        var headers: [String: String] = [
            "User-Agent": settings.userAgent,
            "Accept": "*/*",
            "Connection": "close"
        ]
        for (name, value) in settings.resolvedHeaders {
            headers[name] = value
        }
        config.httpAdditionalHeaders = headers

        let delegate = ProxyAuthDelegate(username: row.username, password: row.password)
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    private static func makeRequest(url: URL, timeout: TimeInterval) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return request
    }

    static func fetchRealIP() async -> String? {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        guard let url = URL(string: "http://ip-api.com/json/?fields=query") else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            return (try? JSONDecoder().decode(ExitIPResponse.self, from: data))?.query
        } catch {
            return nil
        }
    }

    static func check(row: ProxyRow, settings: CheckSettings, realIP: String?) async -> CheckOutcome {
        var outcome = CheckOutcome()

        let type: ProxyType
        if let forced = settings.typeMode.forcedType {
            type = forced
            outcome.supportedTypes = [forced]
        } else if let declared = row.declaredType, declared != .unknown {
            type = declared
            outcome.supportedTypes = [declared]
        } else {
            let detected = await ProxyProbe.detectAll(host: row.host,
                                                      port: row.port,
                                                      timeout: min(settings.timeoutSeconds, 8))
            guard let primary = ProxyType.primary(of: detected) else {
                outcome.status = .failed
                outcome.error = "No proxy protocol detected on \(row.endpoint)"
                return outcome
            }
            type = primary
            outcome.supportedTypes = detected
        }
        outcome.type = type

        guard let targetURL = URL(string: settings.targetURL) else {
            outcome.status = .failed
            outcome.error = "Invalid target URL"
            return outcome
        }

        let session = makeSession(row: row, type: type, settings: settings)
        defer { session.finishTasksAndInvalidate() }

        let request = makeRequest(url: targetURL, timeout: settings.timeoutSeconds)

        let start = DispatchTime.now()
        var body = Data()

        do {

            let (data, statusCode) = try await withTimeout(settings.timeoutSeconds + 1) { () -> (Data, Int) in
                let (data, response) = try await session.data(for: request)
                return (data, (response as? HTTPURLResponse)?.statusCode ?? 200)
            }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
            body = data
            outcome.statusCode = statusCode

            if [401, 407, 502, 503].contains(statusCode) {
                outcome.status = .failed
                outcome.error = "Proxy returned HTTP \(statusCode)"
                return outcome
            }

            let ms = Int(elapsed.rounded())
            outcome.speedMs = ms
            outcome.status = ms > settings.slowThresholdMs ? .slow : .good

        } catch is TimeoutError {
            outcome.status = .timeout
            outcome.error = "Timed out after \(Int(settings.timeoutSeconds))s"
            return outcome
        } catch let urlError as URLError {
            switch urlError.code {
            case .timedOut:
                outcome.status = .timeout
                outcome.error = "Timed out"
            default:
                outcome.status = .failed
                outcome.error = urlError.localizedDescription
            }
            return outcome
        } catch {
            outcome.status = .failed
            outcome.error = error.localizedDescription
            return outcome
        }

        if settings.lookupGeo, settings.geoSource == .exitIP {
            if settings.targetIsGeoEndpoint,
               let decoded = try? JSONDecoder().decode(ExitIPResponse.self, from: body),
               let ip = decoded.query {
                outcome.exitIP = ip
            } else {
                outcome.exitIP = await fetchExitIP(session: session, settings: settings)
            }
        }

        if settings.detectAnonymity {
            outcome.anonymity = await detectAnonymity(session: session,
                                                      settings: settings,
                                                      realIP: realIP)
        }

        return outcome
    }

    private static func fetchExitIP(session: URLSession, settings: CheckSettings) async -> String? {
        guard let url = URL(string: CheckSettings.exitIPEndpoint) else { return nil }
        let request = makeRequest(url: url, timeout: settings.timeoutSeconds)
        do {
            let data = try await withTimeout(settings.timeoutSeconds + 1) { () -> Data in
                try await session.data(for: request).0
            }
            return (try? JSONDecoder().decode(ExitIPResponse.self, from: data))?.query
        } catch {
            return nil
        }
    }

    private static let leakHeaders = [
        "X-FORWARDED-FOR", "X_FORWARDED_FOR", "FORWARDED-FOR", "FORWARDED_FOR",
        "X-FORWARDED", "FORWARDED", "CLIENT-IP", "CLIENT_IP", "X-REAL-IP",
        "X_REAL_IP", "PROXY-CONNECTION", "VIA", "X-PROXY-ID", "HTTP_VIA"
    ]

    private static func detectAnonymity(session: URLSession,
                                        settings: CheckSettings,
                                        realIP: String?) async -> Anonymity {
        guard let url = URL(string: settings.judgeURL) else { return .unknown }
        let request = makeRequest(url: url, timeout: settings.timeoutSeconds)

        do {
            let data = try await withTimeout(settings.timeoutSeconds + 1) { () -> Data in
                try await session.data(for: request).0
            }
            let body = String(decoding: data, as: UTF8.self).uppercased()

            if let realIP, !realIP.isEmpty, body.contains(realIP.uppercased()) {
                return .transparent
            }
            if leakHeaders.contains(where: { body.contains($0) }) {
                return .anonymous
            }
            return .elite
        } catch {
            return .unknown
        }
    }

    static func run(rows: [ProxyRow],
                    settings: CheckSettings,
                    realIP: String?,
                    isCancelled: @escaping @Sendable () -> Bool,
                    onStart: @escaping @Sendable (UUID) -> Void,
                    onResult: @escaping @Sendable (UUID, CheckOutcome) -> Void) async {

        let concurrency = max(1, min(settings.threads, 2000))

        await withTaskGroup(of: Void.self) { group in
            var index = 0
            var inFlight = 0

            func addNext() {
                guard index < rows.count, !isCancelled() else { return }
                let row = rows[index]
                index += 1
                inFlight += 1
                group.addTask {
                    guard !isCancelled() else { return }
                    onStart(row.id)

                    var outcome = await check(row: row, settings: settings, realIP: realIP)
                    var attempt = 0
                    while attempt < settings.retries,
                          outcome.status == .failed || outcome.status == .timeout,
                          !isCancelled() {
                        attempt += 1
                        outcome = await check(row: row, settings: settings, realIP: realIP)
                    }
                    onResult(row.id, outcome)
                }
            }

            while inFlight < concurrency && index < rows.count {
                addNext()
            }
            while await group.next() != nil {
                inFlight -= 1
                addNext()
            }
        }
    }
}
