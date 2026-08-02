import Foundation

enum Exporter {

    struct Summary {
        var fileCount: Int
        var proxyCount: Int
        var directory: URL
    }

    static func export(rows: [ProxyRow],
                       filter: ExportFilter,
                       format: ExportFormat,
                       grouping: ExportGrouping,
                       to directory: URL,
                       baseName: String = "proxies") throws -> Summary {

        let matching = rows.filter { filter.matches($0) }
        guard !matching.isEmpty else {
            return Summary(fileCount: 0, proxyCount: 0, directory: directory)
        }

        var buckets: [String: [ProxyRow]] = [:]
        for row in matching {
            for key in bucketKeys(for: row, grouping: grouping) {
                buckets[key, default: []].append(row)
            }
        }

        var written = 0
        for (key, group) in buckets {
            let sorted = group.sorted { ($0.speedMs ?? Int.max) < ($1.speedMs ?? Int.max) }
            let contents = render(rows: sorted, format: format)
            let name = key.isEmpty ? baseName : "\(baseName)_\(sanitize(key))"
            let url = directory.appendingPathComponent("\(name).\(format.fileExtension)")
            try contents.write(to: url, atomically: true, encoding: .utf8)
            written += 1
        }

        return Summary(fileCount: written, proxyCount: matching.count, directory: directory)
    }

    static func render(rows: [ProxyRow], format: ExportFormat) -> String {
        switch format {
        case .csv:
            return renderCSV(rows: rows)
        case .json:
            return renderJSON(rows: rows)
        default:
            return rows.map { $0.formatted(format) }.joined(separator: "\n") + "\n"
        }
    }

    private static let csvHeader =
        "host,port,username,password,type,protocols,status,http_code,speed_ms,exit_ip,country,country_code,state,isp,security"

    private static func renderCSV(rows: [ProxyRow]) -> String {
        var lines: [String] = [csvHeader]
        lines.reserveCapacity(rows.count + 1)

        for row in rows {

            var fields: [String] = []
            fields.reserveCapacity(15)
            fields.append(row.host)
            fields.append(String(row.port))
            fields.append(row.username ?? "")
            fields.append(row.password ?? "")
            fields.append(row.resolvedType.label)
            fields.append(exportProtocols(row).map(\.label).joined(separator: "|"))
            fields.append(row.status.label)
            if let code = row.statusCode {
                fields.append(String(code))
            } else {
                fields.append("")
            }
            if let ms = row.speedMs {
                fields.append(String(ms))
            } else {
                fields.append("")
            }
            fields.append(row.exitIP ?? "")
            fields.append(row.country ?? "")
            fields.append(row.countryCode ?? "")
            fields.append(row.state ?? "")
            fields.append(row.isp ?? "")
            fields.append(row.anonymity.label)

            lines.append(fields.map(csvEscape).joined(separator: ","))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderJSON(rows: [ProxyRow]) -> String {
        var objects: [[String: Any]] = []
        objects.reserveCapacity(rows.count)

        for row in rows {
            var dict: [String: Any] = [:]
            dict["host"] = row.host
            dict["port"] = row.port
            dict["type"] = row.resolvedType.rawValue
            dict["protocols"] = exportProtocols(row).map(\.rawValue)
            dict["status"] = row.status.rawValue
            dict["security"] = row.anonymity.rawValue

            if let user = row.username, !user.isEmpty {
                dict["username"] = user
                dict["password"] = row.password ?? ""
            }
            if let code = row.statusCode { dict["http_code"] = code }
            if let ms = row.speedMs { dict["speed_ms"] = ms }
            if let ip = row.exitIP { dict["exit_ip"] = ip }
            if let country = row.country { dict["country"] = country }
            if let code = row.countryCode { dict["country_code"] = code }
            if let state = row.state { dict["state"] = state }
            if let isp = row.isp { dict["isp"] = isp }

            objects.append(dict)
        }

        guard let data = try? JSONSerialization.data(withJSONObject: objects,
                                                     options: [.prettyPrinted, .sortedKeys]) else {
            return "[]\n"
        }
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    static func exportProtocols(_ row: ProxyRow) -> [ProxyType] {
        let set = row.supportedTypes.isEmpty ? [row.resolvedType] : row.supportedTypes
        return ProxyType.detectionOrder.filter { set.contains($0) }
    }

    private static func bucketKeys(for row: ProxyRow, grouping: ExportGrouping) -> [String] {
        switch grouping {
        case .single: return [""]
        case .byType:
            let protocols = exportProtocols(row)
            return protocols.isEmpty ? [row.resolvedType.label] : protocols.map(\.label)
        case .byCountry: return [row.country ?? "Unknown"]
        case .byState: return [row.state ?? "Unknown"]
        case .byAnonymity: return [row.anonymity.label]
        case .bySpeed: return [SpeedBand.band(for: row.speedMs).rawValue]
        }
    }

    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var out = ""
        out.reserveCapacity(name.count)
        for scalar in name.unicodeScalars {
            out.append(allowed.contains(scalar) ? Character(scalar) : "-")
        }
        return out.lowercased()
    }

    private static func csvEscape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
