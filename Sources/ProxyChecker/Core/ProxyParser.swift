import Foundation

enum ProxyParser {

    struct Result {
        var rows: [ProxyRow] = []
        var skipped: Int = 0
        var duplicates: Int = 0
    }

    static func parse(_ text: String, dedupe: Bool = true) -> Result {
        var result = Result()
        var seen = Set<String>()

        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if line.hasPrefix("#") || line.hasPrefix("//") { continue }

            for token in tokenize(line) {
                guard let row = parseToken(token) else {
                    result.skipped += 1
                    continue
                }

                if dedupe {
                    let key = "\(row.host.lowercased()):\(row.port):\(row.username ?? "")"
                    if seen.contains(key) {
                        result.duplicates += 1
                        continue
                    }
                    seen.insert(key)
                }
                result.rows.append(row)
            }
        }
        return result
    }

    private static let separators = CharacterSet(charactersIn: ",\t; ")

    private static func tokenize(_ line: String) -> [String] {
        let pieces = line.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard pieces.count > 1 else { return [line] }

        if pieces.count >= 2, Int(pieces[1]) != nil, (1...65535).contains(Int(pieces[1]) ?? 0) {
            return [pieces.joined(separator: ":")]
        }

        return pieces
    }

    static func parseToken(_ input: String) -> ProxyRow? {
        var line = input.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }

        var declaredType: ProxyType?
        if let range = line.range(of: "://") {
            let scheme = String(line[line.startIndex..<range.lowerBound])
            declaredType = ProxyType.from(scheme: scheme)
            line = String(line[range.upperBound...])
        }

        if let slash = line.firstIndex(of: "/") {
            line = String(line[line.startIndex..<slash])
        }
        guard !line.isEmpty else { return nil }

        var user: String?
        var pass: String?
        var hostPart = line

        if let at = line.lastIndex(of: "@") {
            let credentials = String(line[line.startIndex..<at])
            hostPart = String(line[line.index(after: at)...])
            let creds = credentials.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if creds.count == 2 {
                user = String(creds[0])
                pass = String(creds[1])
            } else if creds.count == 1, !creds[0].isEmpty {
                user = String(creds[0])
                pass = ""
            }
        }

        let fields = hostPart.split(separator: ":", omittingEmptySubsequences: false).map(String.init)

        switch fields.count {
        case 2:
            guard let port = validPort(fields[1]), isValidHost(fields[0]) else { return nil }
            return ProxyRow(host: fields[0], port: port, username: user, password: pass, declaredType: declaredType)

        case 3:

            guard let port = validPort(fields[1]), isValidHost(fields[0]) else { return nil }
            return ProxyRow(host: fields[0], port: port, username: fields[2], password: "", declaredType: declaredType)

        case 4:

            if let port = validPort(fields[1]), isValidHost(fields[0]) {
                return ProxyRow(host: fields[0], port: port,
                                username: fields[2], password: fields[3],
                                declaredType: declaredType)
            }
            if let port = validPort(fields[3]), isValidHost(fields[2]) {
                return ProxyRow(host: fields[2], port: port,
                                username: fields[0], password: fields[1],
                                declaredType: declaredType)
            }
            return nil

        default:
            return nil
        }
    }

    static func parseLine(_ input: String) -> ProxyRow? {
        parseToken(input)
    }

    private static func validPort(_ s: String) -> Int? {
        guard let p = Int(s.trimmingCharacters(in: .whitespaces)), (1...65535).contains(p) else { return nil }
        return p
    }

    private static let hostCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"
    )

    private static func isValidHost(_ s: String) -> Bool {
        let host = s.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, host.count <= 253 else { return false }
        return host.unicodeScalars.allSatisfy { hostCharacters.contains($0) }
    }
}
