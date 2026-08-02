import Foundation
import Network

struct TimeoutError: Error, CustomStringConvertible {
    var description: String { "Timed out" }
}

enum ProbeError: Error, CustomStringConvertible {
    case cancelled
    case closed
    case notAProxy

    var description: String {
        switch self {
        case .cancelled: return "Connection cancelled"
        case .closed: return "Connection closed"
        case .notAProxy: return "No proxy protocol detected"
        }
    }
}

func withTimeout<T: Sendable>(_ seconds: TimeInterval,
                              operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(max(0.1, seconds) * 1_000_000_000))
            throw TimeoutError()
        }
        guard let first = try await group.next() else { throw TimeoutError() }
        group.cancelAll()
        return first
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func run(_ body: () -> Void) {
        lock.lock()
        let shouldRun = !fired
        fired = true
        lock.unlock()
        if shouldRun { body() }
    }
}

final class TCPClient: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "proxychecker.tcp", qos: .userInitiated)

    init(host: String, port: UInt16) {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        if let tcp = params.defaultProtocolStack.internetProtocol as? NWProtocolTCP.Options {
            tcp.connectionTimeout = 10
            tcp.noDelay = true
        }
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? .http,
            using: params
        )
    }

    func connect() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = Once()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.run { cont.resume() }
                case .failed(let error):
                    once.run { cont.resume(throwing: error) }
                case .waiting(let error):
                    once.run { cont.resume(throwing: error) }
                case .cancelled:
                    once.run { cont.resume(throwing: ProbeError.cancelled) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let once = Once()
            connection.send(content: data, completion: .contentProcessed { error in
                once.run {
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            })
        }
    }

    func receive(min: Int, max: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            let once = Once()
            connection.receive(minimumIncompleteLength: min, maximumLength: max) { data, _, _, error in
                once.run {
                    if let error {
                        cont.resume(throwing: error)
                    } else if let data, !data.isEmpty {
                        cont.resume(returning: data)
                    } else {
                        cont.resume(throwing: ProbeError.closed)
                    }
                }
            }
        }
    }

    func close() {
        connection.stateUpdateHandler = nil
        connection.cancel()
    }
}

enum ProxyProbe {

    static func detectType(host: String, port: Int, timeout: TimeInterval) async -> ProxyType? {
        if await probeSOCKS5(host: host, port: port, timeout: timeout) { return .socks5 }
        if await probeHTTP(host: host, port: port, timeout: timeout) { return .http }
        if await probeSOCKS4(host: host, port: port, timeout: timeout) { return .socks4 }
        return nil
    }

    private static func probeSOCKS5(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        await runProbe(host: host, port: port, timeout: timeout) { client in
            try await client.send(Data([0x05, 0x02, 0x00, 0x02]))
            let reply = try await client.receive(min: 2, max: 2)
            return reply.count >= 2 && reply[reply.startIndex] == 0x05
        }
    }

    private static func probeSOCKS4(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        await runProbe(host: host, port: port, timeout: timeout) { client in
            var request = Data([0x04, 0x01, 0x00, 0x50, 0x01, 0x01, 0x01, 0x01])
            request.append(contentsOf: Array("pc".utf8))
            request.append(0x00)
            try await client.send(request)
            let reply = try await client.receive(min: 8, max: 8)
            guard reply.count >= 2 else { return false }
            let bytes = [UInt8](reply)
            return bytes[0] == 0x00 && (0x5A...0x5D).contains(bytes[1])
        }
    }

    private static func probeHTTP(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        await runProbe(host: host, port: port, timeout: timeout) { client in
            let request = "CONNECT ip-api.com:80 HTTP/1.1\r\nHost: ip-api.com:80\r\nProxy-Connection: close\r\n\r\n"
            try await client.send(Data(request.utf8))
            let reply = try await client.receive(min: 1, max: 256)
            let text = String(decoding: reply, as: UTF8.self).uppercased()
            return text.hasPrefix("HTTP/")
        }
    }

    private static func runProbe(host: String,
                                 port: Int,
                                 timeout: TimeInterval,
                                 body: @escaping @Sendable (TCPClient) async throws -> Bool) async -> Bool {
        let client = TCPClient(host: host, port: UInt16(clamping: port))
        defer { client.close() }
        do {
            return try await withTimeout(timeout) {
                try await client.connect()
                return try await body(client)
            }
        } catch {
            return false
        }
    }
}
