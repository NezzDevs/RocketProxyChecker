import SwiftUI
import AppKit

struct DetailsTable: View {
    @Environment(AppModel.self) private var model
    @Environment(ColumnLayout.self) private var layout

    var body: some View {
        let rows = model.visibleRows

        GeometryReader { proxy in
            let contentWidth = max(layout.total, proxy.size.width)
            let metrics = ColumnMetrics.make(base: layout.baseWidths, available: proxy.size.width)

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    header(metrics: metrics)

                    if rows.isEmpty {
                        emptyState
                    } else {
                        ScrollView(.vertical) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                    DetailRow(row: row,
                                              zebra: index.isMultiple(of: 2),
                                              showPassword: model.showPasswords,
                                              metrics: metrics)
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

    private func header(metrics: ColumnMetrics) -> some View {
        HStack(spacing: 0) {
            ForEach(ColumnID.allCases) { column in
                headerCell(column, metrics: metrics)
            }
        }
        .frame(height: 42)
        .background(Theme.headerRow)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairlineStrong).frame(height: 1)
        }
        .contextMenu {
            Button("Reset column widths") { layout.resetAll() }
        }
    }

    @ViewBuilder
    private func headerCell(_ column: ColumnID, metrics: ColumnMetrics) -> some View {
        Group {
            if let sort = column.sortColumn {
                Button {
                    model.toggleSort(sort)
                } label: {
                    headerLabel(column, isActive: model.sortColumn == sort, metrics: metrics)
                }
                .buttonStyle(.plain)
            } else {
                headerLabel(column, isActive: false, metrics: metrics)
            }
        }
        .overlay(alignment: .trailing) {
            if !ColumnID.isLast(column) {
                Rectangle()
                    .fill(Theme.hairlineStrong)
                    .frame(width: 1)
            }
        }
        .overlay(alignment: .trailing) {
            if !ColumnID.isLast(column) {
                ResizeHandle(column: column, scale: metrics.scale)
            }
        }
    }

    private func headerLabel(_ column: ColumnID, isActive: Bool, metrics: ColumnMetrics) -> some View {
        HStack(spacing: 4) {
            Text(column.title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            if column.sortColumn != nil {
                Image(systemName: isActive
                      ? (model.sortAscending ? "chevron.up" : "chevron.down")
                      : "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isActive ? Theme.textSecondary : Theme.textFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: metrics.width(column), height: 42, alignment: .leading)
        .contentShape(Rectangle())
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

private struct ResizeHandle: View {
    let column: ColumnID
    let scale: CGFloat
    @Environment(ColumnLayout.self) private var layout

    @State private var startWidth: CGFloat?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering || startWidth != nil ? Theme.textSecondary : Color.clear)
            .frame(width: hovering || startWidth != nil ? 2 : 1)
            .frame(width: 9)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside {
                    NSCursor.resizeLeftRight.set()
                } else if startWidth == nil {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let base: CGFloat
                        if let startWidth {
                            base = startWidth
                        } else {
                            base = layout.width(column)
                            startWidth = base
                        }
                        layout.setWidth(base + value.translation.width / max(scale, 0.01), for: column)
                    }
                    .onEnded { _ in
                        startWidth = nil
                        if !hovering { NSCursor.arrow.set() }
                    }
            )
            .onTapGesture(count: 2) { layout.reset(column) }
            .help("Drag to resize. Double-click to reset.")
    }
}

private struct DetailRow: View {
    let row: ProxyRow
    let zebra: Bool
    let showPassword: Bool
    let metrics: ColumnMetrics

    @Environment(ColumnLayout.self) private var layout
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ColumnID.allCases) { column in
                cell(column)
            }
        }
        .font(.system(size: 13))
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
    private func cell(_ column: ColumnID) -> some View {
        content(column)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 12)
            .frame(width: metrics.width(column), height: Theme.rowHeight, alignment: .leading)
            .overlay(alignment: .trailing) {
                if !ColumnID.isLast(column) {
                    Rectangle().fill(Theme.hairline).frame(width: 1)
                }
            }
    }

    @ViewBuilder
    private func content(_ column: ColumnID) -> some View {
        switch column {
        case .host:
            Text(row.host)
                .font(.mono(12.5))
                .foregroundStyle(Theme.textPrimary)

        case .port:
            Text(verbatim: String(row.port))
                .font(.mono(12.5))
                .foregroundStyle(Theme.textPrimary)

        case .username:
            Text(row.username ?? "—")
                .font(.mono(12.5))
                .foregroundStyle(row.username == nil ? Theme.textFaint : Theme.textPrimary)

        case .password:
            if let password = row.password, !password.isEmpty {
                Text(showPassword ? password : String(repeating: "•", count: min(password.count, 14)))
                    .font(.mono(12.5))
                    .foregroundStyle(showPassword ? Theme.textPrimary : Theme.textSecondary)
            } else {
                Text("—").font(.mono(12.5)).foregroundStyle(Theme.textFaint)
            }

        case .statusCode:
            if let code = row.statusCode {
                Text(verbatim: String(code))
                    .font(.mono(12.5))
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Text("—").font(.mono(12.5)).foregroundStyle(Theme.textFaint)
            }

        case .country:
            Text(row.country ?? "—")
                .foregroundStyle(row.country == nil ? Theme.textFaint : Theme.textPrimary)

        case .state:
            Text(row.state ?? "—")
                .foregroundStyle(row.state == nil ? Theme.textFaint : Theme.textPrimary)

        case .isp:
            Text(row.isp ?? "—")
                .foregroundStyle(row.isp == nil ? Theme.textFaint : Theme.textPrimary)

        case .network:
            Text(row.network.label)
                .font(.system(size: 12))
                .foregroundStyle(row.network == .unknown ? Theme.textFaint : Theme.textPrimary)

        case .type:
            Text(row.resolvedType.label)
                .font(.mono(11.5, .medium))
                .foregroundStyle(row.resolvedType == .unknown ? Theme.textFaint : Theme.textPrimary)

        case .security:
            Text(row.anonymity.label)
                .font(.system(size: 12))
                .foregroundStyle(row.anonymity == .unknown ? Theme.textFaint : Theme.textPrimary)

        case .speed:
            speedContent
        }
    }

    @ViewBuilder
    private var speedContent: some View {
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
