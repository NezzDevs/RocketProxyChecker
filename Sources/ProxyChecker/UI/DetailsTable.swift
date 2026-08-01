import SwiftUI
import AppKit

enum Columns {
    static let host: CGFloat = 200
    static let port: CGFloat = 72
    static let username: CGFloat = 180
    static let password: CGFloat = 150
    static let statusCode: CGFloat = 84
    static let country: CGFloat = 130
    static let state: CGFloat = 120
    static let isp: CGFloat = 180
    static let type: CGFloat = 88
    static let security: CGFloat = 110
    static let speed: CGFloat = 100

    static var total: CGFloat {
        host + port + username + password + statusCode
            + country + state + isp + type + security + speed + 44
    }

    static var windowWidth: CGFloat { total + 28 + 24 }
}

struct DetailsTable: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let rows = model.visibleRows

        GeometryReader { proxy in
            let contentWidth = max(Columns.total, proxy.size.width)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    header

                    if rows.isEmpty {
                        emptyState
                    } else {
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                    DetailRow(row: row,
                                              zebra: index.isMultiple(of: 2),
                                              showPassword: model.showPasswords)
                                }
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
                .frame(width: contentWidth, alignment: .leading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }

    private var header: some View {

        HStack(spacing: 0) {
            headerLabel("HOST", width: Columns.host)
            headerLabel("PORT", width: Columns.port)
            headerLabel("USERNAME", width: Columns.username)
            headerLabel("PASSWORD", width: Columns.password)
            headerLabel("STATUS", width: Columns.statusCode)
            headerLabel("COUNTRY", width: Columns.country)
            headerLabel("STATE", width: Columns.state)
            sortableHeader("ISP", .isp, width: Columns.isp)
            sortableHeader("TYPE", .type, width: Columns.type)
            sortableHeader("SECURITY", .security, width: Columns.security)
            headerLabel("SPEED", width: Columns.speed)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .frame(height: 42)
        .background(Theme.headerRow)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairlineStrong).frame(height: 1)
        }
    }

    private func headerLabel(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.textSecondary)
            .frame(width: width, alignment: .leading)
    }

    @ViewBuilder
    private func sortableHeader(_ title: String, _ column: SortColumn, width: CGFloat) -> some View {
        let isActive = model.sortColumn == column

        Button {
            model.toggleSort(column)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(isActive ? Theme.textPrimary : Theme.textSecondary)
                Image(systemName: isActive
                      ? (model.sortAscending ? "chevron.up" : "chevron.down")
                      : "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isActive ? Theme.textSecondary : Theme.textFaint)
                Spacer(minLength: 0)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isActive && !model.sortAscending
              ? "Click to sort by speed again"
              : "Sort by \(title.lowercased())")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 26))
                .foregroundStyle(Theme.textFaint)
            Text(model.total == 0 ? "No proxies loaded" : "No proxies match this filter")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text(model.total == 0
                 ? "Add a list to start checking."
                 : "Clear the search field or the status filter above.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textFaint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 90)
    }
}

private struct DetailRow: View {
    let row: ProxyRow
    let zebra: Bool
    let showPassword: Bool

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Text(row.host)
                .font(.mono(12.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Columns.host, alignment: .leading)

            Text(verbatim: String(row.port))
                .font(.mono(12.5))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: Columns.port, alignment: .leading)

            Text(row.username ?? "—")
                .font(.mono(12.5))
                .foregroundStyle(row.username == nil ? Theme.textFaint : Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Columns.username, alignment: .leading)

            Group {
                if let password = row.password, !password.isEmpty {
                    Text(showPassword ? password : String(repeating: "•", count: min(password.count, 14)))
                        .font(.mono(12.5))
                        .foregroundStyle(showPassword ? Theme.textPrimary : Theme.textSecondary)
                } else {
                    Text("—").font(.mono(12.5)).foregroundStyle(Theme.textFaint)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: Columns.password, alignment: .leading)

            statusCodeCell
                .frame(width: Columns.statusCode, alignment: .leading)

            Text(row.country ?? "—")
                .foregroundStyle(row.country == nil ? Theme.textFaint : Theme.textPrimary)
                .lineLimit(1)
                .frame(width: Columns.country, alignment: .leading)

            Text(row.state ?? "—")
                .foregroundStyle(row.state == nil ? Theme.textFaint : Theme.textPrimary)
                .lineLimit(1)
                .frame(width: Columns.state, alignment: .leading)

            Text(row.isp ?? "—")
                .foregroundStyle(row.isp == nil ? Theme.textFaint : Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Columns.isp, alignment: .leading)

            Text(row.resolvedType.label)
                .font(.mono(11.5, .medium))
                .foregroundStyle(row.resolvedType == .unknown ? Theme.textFaint : Theme.textSecondary)
                .frame(width: Columns.type, alignment: .leading)

            Text(row.anonymity.label)
                .font(.system(size: 12))
                .foregroundStyle(row.anonymity == .unknown ? Theme.textFaint : Theme.textSecondary)
                .frame(width: Columns.security, alignment: .leading)

            statusCell
                .frame(width: Columns.speed, alignment: .leading)

            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 22)
        .frame(height: Theme.rowHeight)
        .background(hovering ? Theme.rowHover : (zebra ? Theme.rowAlt : Theme.panel))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
        .onHover { hovering = $0 }
        .help(row.error ?? "")
        .contextMenu {
            Button("Copy host:port") { copy(row.endpoint) }
            Button("Copy full line") { copy(row.formatted(.schemeURL)) }
            if let ip = row.exitIP {
                Button("Copy exit IP (\(ip))") { copy(ip) }
            }
            if let error = row.error {
                Divider()
                Text(error)
            }
        }
    }

    @ViewBuilder
    private var statusCodeCell: some View {
        if let code = row.statusCode {
            Text(verbatim: String(code))
                .font(.mono(12.5))
                .foregroundStyle(Theme.textPrimary)
        } else {
            Text("—")
                .font(.mono(12.5))
                .foregroundStyle(Theme.textFaint)
        }
    }

    @ViewBuilder
    private var statusCell: some View {
        switch row.status {
        case .good, .slow:
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.speedColor(row.speedMs ?? 0))
                    .frame(width: 6, height: 6)
                Text(verbatim: "\(row.speedMs ?? 0) ms")
                    .font(.mono(12))
                    .foregroundStyle(Theme.speedColor(row.speedMs ?? 0))
            }
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).scaleEffect(0.55)
                Text("checking").font(.mono(11)).foregroundStyle(Theme.textFaint)
            }
        default:
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.color(for: row.status))
                    .frame(width: 6, height: 6)
                Text(row.status.label.lowercased())
                    .font(.mono(12))
                    .foregroundStyle(Theme.color(for: row.status))
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
