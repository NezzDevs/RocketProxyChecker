import SwiftUI

struct SettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Settings",
                        subtitle: "Applies to the next run.")

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {

                    SettingsGroup("Performance") {
                        SliderRow(
                            label: "Threads",
                            help: "Checks running at once. 100–300 suits Apple silicon.",
                            value: $model.settings.threads,
                            range: 1...1000,
                            display: { "\($0)" }
                        )

                        SliderRow(
                            label: "Timeout",
                            help: "A proxy that hasn't answered by then counts as timed out.",
                            value: Binding(
                                get: { Int(model.settings.timeoutSeconds) },
                                set: { model.settings.timeoutSeconds = Double($0) }
                            ),
                            range: 1...60,
                            display: { "\($0)s" }
                        )

                        SliderRow(
                            label: "Slow above",
                            help: "Working proxies over this latency are marked slow, not good.",
                            value: $model.settings.slowThresholdMs,
                            range: 100...10000,
                            step: 50,
                            display: { "\($0) ms" }
                        )

                        SettingRow("Retries", help: "Extra attempts for proxies that fail or time out.") {
                            Picker("", selection: $model.settings.retries) {
                                Text("None").tag(0)
                                ForEach(1...5, id: \.self) { n in
                                    Text(verbatim: "\(n)").tag(n)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 260)
                        }
                    }

                    SettingsGroup("Protocol") {
                        SettingRow("Detection", help: "Auto probes each proxy for SOCKS5, HTTP, then SOCKS4.") {
                            Picker("", selection: $model.settings.typeMode) {
                                ForEach(TypeMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 260)
                        }
                    }

                    SettingsGroup("Location") {
                        SettingRow("Look up location", help: "Adds country, state and ISP to each working proxy.") {
                            Toggle("", isOn: $model.settings.lookupGeo)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        if model.settings.lookupGeo {
                            SettingRow("Locate by", help: model.settings.geoSource.help) {
                                Picker("", selection: $model.settings.geoSource) {
                                    ForEach(GeoSource.allCases) { source in
                                        Text(source.label).tag(source)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 260)
                            }

                            SettingRow("Cached results", help: "Kept 30 days so repeat runs cost no requests.") {
                                Button("Clear cache") { model.clearGeoCache() }
                                    .buttonStyle(BarButtonStyle())
                            }
                        }
                    }

                    SettingsGroup("Security type") {
                        SettingRow("Detect anonymity", help: "One extra request per proxy. Sorts elite, anonymous and transparent.") {
                            Toggle("", isOn: $model.settings.detectAnonymity)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        if model.settings.detectAnonymity {
                            SettingRow("Judge URL", help: "Any page that echoes the request headers back.") {
                                FieldBox {
                                    TextField("http://azenv.net/", text: $model.settings.judgeURL)
                                        .textFieldStyle(.plain)
                                        .font(.mono(12))
                                }
                            }
                        }
                    }

                    SettingsGroup("Request") {
                        SettingRow("User agent", help: "Sent with every check.") {
                            FieldBox {
                                TextField("User agent", text: $model.settings.userAgent, axis: .vertical)
                                    .textFieldStyle(.plain)
                                    .font(.mono(11))
                                    .lineLimit(2...3)
                            }
                        }

                        SettingRow("Custom headers", help: "Added to every request. Overrides a default of the same name.") {
                            HeaderEditor(headers: $model.settings.customHeaders)
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
            }

            Divider().overlay(Theme.hairline)

            HStack {
                Button("Reset to defaults") { model.settings = CheckSettings() }
                    .buttonStyle(BarButtonStyle())
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(BarButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 740, height: 660)
        .background(Theme.background)
    }
}

struct SheetHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .background(Theme.panel)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 1)
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(height: 1)
            }
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 18) {
                content
            }
        }
    }
}

struct SettingRow<Content: View>: View {
    let label: String
    let help: String?
    @ViewBuilder var content: Content

    init(_ label: String, help: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.help = help
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                if let help {
                    Text(help)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 210, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SliderRow: View {
    let label: String
    let help: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    let display: (Int) -> String

    var body: some View {
        SettingRow(label, help: help) {
            HStack(spacing: 16) {
                Slider(
                    value: Binding(
                        get: { Double(value) },
                        set: { value = quantize($0) }
                    ),
                    in: Double(range.lowerBound)...Double(range.upperBound)
                )
                .controlSize(.small)
                .tint(Theme.textSecondary)

                Text(verbatim: display(value))
                    .font(.mono(12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .frame(width: 70, alignment: .trailing)
            }
        }
    }

    private func quantize(_ raw: Double) -> Int {
        let stepped = (raw / Double(step)).rounded() * Double(step)
        return min(max(Int(stepped), range.lowerBound), range.upperBound)
    }
}

struct FieldBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.panelRaised))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.hairline, lineWidth: 1))
    }
}
