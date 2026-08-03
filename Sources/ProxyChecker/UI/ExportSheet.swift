import SwiftUI

struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var format: ExportFormat = .schemeURL
    @State private var grouping: ExportGrouping = .single
    @State private var baseName = "proxies"

    private var fileNameHelp: String {
        "Saved as \(Exporter.safeStem(baseName))_<group>.\(format.fileExtension)"
    }

    private var matchCount: Int {
        model.rows.lazy.filter { model.exportFilter.matches($0) }.count
    }

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Export proxies",
                        subtitle: "Pick what to include, how to write it, and how to split the files.")

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {

                    SettingsGroup("Include") {
                        SettingRow("Status") {
                            FlowChips(
                                options: [ProxyStatus.good, .slow, .timeout, .failed].map { ($0.rawValue, $0.label) },
                                selection: $model.exportFilter.statuses
                            )
                        }

                        SettingRow("Type", help: "Leave empty for every type.") {
                            FlowChips(
                                options: [ProxyType.http, .https, .socks4, .socks5].map { ($0.rawValue, $0.label) },
                                selection: $model.exportFilter.types
                            )
                        }

                        SettingRow("Security", help: "Leave empty for every security type.") {
                            FlowChips(
                                options: [Anonymity.elite, .anonymous, .transparent].map { ($0.rawValue, $0.label) },
                                selection: $model.exportFilter.anonymities
                            )
                        }

                        SettingRow("Network", help: "Leave empty for every network type.") {
                            FlowChips(
                                options: [NetworkType.residential, .datacenter, .mobile].map { ($0.rawValue, $0.label) },
                                selection: $model.exportFilter.networks
                            )
                        }

                        if !model.availableCountries.isEmpty {
                            SettingRow("Country", help: "Leave empty for every country.") {
                                FlowChips(
                                    options: model.availableCountries.map { ($0, $0) },
                                    selection: $model.exportFilter.countries
                                )
                            }
                        }

                        if !model.availableStates.isEmpty {
                            SettingRow("State", help: "Leave empty for every state.") {
                                FlowChips(
                                    options: model.availableStates.map { ($0, $0) },
                                    selection: $model.exportFilter.states
                                )
                            }
                        }

                        SettingRow("Max speed", help: "0 keeps every speed.") {
                            HStack(spacing: 12) {
                                Slider(value: Binding(
                                    get: { Double(model.exportFilter.maxSpeedMs) },
                                    set: { model.exportFilter.maxSpeedMs = Int(($0 / 50).rounded() * 50) }
                                ), in: 0...10000)
                                .controlSize(.small)
                                .tint(Theme.textSecondary)
                                Text(verbatim: model.exportFilter.maxSpeedMs == 0 ? "any" : "\(model.exportFilter.maxSpeedMs) ms")
                                    .font(.mono(12))
                                    .lineLimit(1)
                                    .frame(width: 70, alignment: .trailing)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                    }

                    SettingsGroup("Write") {
                        SettingRow("Line format") {
                            Picker("", selection: $format) {
                                ForEach(ExportFormat.allCases) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 280)
                        }

                        SettingRow("Split into") {
                            Picker("", selection: $grouping) {
                                ForEach(ExportGrouping.allCases) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 280)
                        }

                        if grouping != .single {
                            SettingRow("File name", help: fileNameHelp) {
                                FieldBox {
                                    TextField("proxies", text: $baseName)
                                        .textFieldStyle(.plain)
                                        .font(.mono(12))
                                }
                                .frame(width: 280)
                            }
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
            }

            Divider().overlay(Theme.hairline)

            HStack(spacing: 10) {
                Text("\(matchCount) proxies match")
                    .font(.system(size: 12))
                    .foregroundStyle(matchCount == 0 ? Theme.failed : Theme.textSecondary)

                Spacer()

                Button("Cancel") { dismiss() }
                    .buttonStyle(BarButtonStyle())

                Button("Copy") {
                    model.copyToClipboard(format: format)
                    dismiss()
                }
                .buttonStyle(BarButtonStyle())
                .disabled(matchCount == 0)

                Button(grouping == .single ? "Save…" : "Choose folder…") {
                    dismiss()
                    model.export(format: format, grouping: grouping, baseName: baseName)
                }
                .buttonStyle(BarButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(matchCount == 0)
            }
            .padding(16)
        }
        .frame(width: 700, height: 640)
        .background(Theme.background)
    }
}

struct FlowChips: View {
    let options: [(id: String, label: String)]
    @Binding var selection: Set<String>

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(options, id: \.id) { option in
                let isOn = selection.contains(option.id)
                Button {
                    if isOn { selection.remove(option.id) } else { selection.insert(option.id) }
                } label: {
                    Text(option.label)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(isOn ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(isOn ? Theme.panelRaised : Color.white.opacity(0.03))
                        )
                        .overlay(
                            Capsule().strokeBorder(isOn ? Theme.hairlineStrong : Theme.hairline, lineWidth: 1)
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 420
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
