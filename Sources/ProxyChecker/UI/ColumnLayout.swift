import SwiftUI
import Observation

enum ColumnID: String, CaseIterable, Identifiable, Codable {
    case host, port, username, password, statusCode, country, state, isp, network, type, security, speed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .host: return "HOST"
        case .port: return "PORT"
        case .username: return "USERNAME"
        case .password: return "PASSWORD"
        case .statusCode: return "STATUS"
        case .country: return "COUNTRY"
        case .state: return "STATE"
        case .isp: return "ISP"
        case .network: return "NETWORK"
        case .type: return "TYPE"
        case .security: return "SECURITY"
        case .speed: return "SPEED"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .host: return 210
        case .port: return 80
        case .username: return 180
        case .password: return 150
        case .statusCode: return 92
        case .country: return 140
        case .state: return 130
        case .isp: return 190
        case .network: return 122
        case .type: return 100
        case .security: return 118
        case .speed: return 110
        }
    }

    var minWidth: CGFloat {
        switch self {
        case .port, .statusCode: return 62
        case .speed, .security: return 80
        default: return 70
        }
    }

    static func isLast(_ column: ColumnID) -> Bool {
        column == allCases.last
    }

    var sortColumn: SortColumn? {
        switch self {
        case .isp: return .isp
        case .network: return .network
        case .type: return .type
        case .security: return .security
        default: return nil
        }
    }
}

struct ColumnMetrics: Equatable {
    var widths: [ColumnID: CGFloat] = [:]
    var scale: CGFloat = 1

    func width(_ column: ColumnID) -> CGFloat {
        widths[column] ?? column.defaultWidth
    }

    static func make(base: [ColumnID: CGFloat], available: CGFloat) -> ColumnMetrics {
        let all = ColumnID.allCases
        let total = all.reduce(0) { $0 + (base[$1] ?? $1.defaultWidth) }
        guard total > 0 else { return ColumnMetrics() }

        let scale = available > total ? available / total : 1
        let target = max(total, available)

        var widths: [ColumnID: CGFloat] = [:]
        var used: CGFloat = 0
        for column in all.dropLast() {
            let value = ((base[column] ?? column.defaultWidth) * scale).rounded()
            widths[column] = value
            used += value
        }
        if let last = all.last {
            widths[last] = max(last.minWidth, target - used)
        }
        return ColumnMetrics(widths: widths, scale: scale)
    }
}

@MainActor
@Observable
final class ColumnLayout {

    private static let storageKey = "ColumnWidths"
    static let maxWidth: CGFloat = 600

    private var widths: [String: CGFloat] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: CGFloat].self, from: data) {
            widths = decoded
        }
    }

    func width(_ id: ColumnID) -> CGFloat {
        widths[id.rawValue] ?? id.defaultWidth
    }

    func setWidth(_ value: CGFloat, for id: ColumnID) {
        widths[id.rawValue] = min(max(value, id.minWidth), Self.maxWidth)
        persist()
    }

    func reset(_ id: ColumnID) {
        widths.removeValue(forKey: id.rawValue)
        persist()
    }

    func resetAll() {
        widths.removeAll()
        persist()
    }

    var total: CGFloat {
        ColumnID.allCases.reduce(0) { $0 + width($1) }
    }

    var baseWidths: [ColumnID: CGFloat] {
        var out: [ColumnID: CGFloat] = [:]
        for column in ColumnID.allCases { out[column] = width(column) }
        return out
    }

    static var defaultTotal: CGFloat {
        ColumnID.allCases.reduce(0) { $0 + $1.defaultWidth }
    }

    static var defaultWindowWidth: CGFloat {
        defaultTotal + 28 + 40
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(widths) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
