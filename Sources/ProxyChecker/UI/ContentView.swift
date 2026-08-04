import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model

    @State private var showSettings = false
    @State private var showExport = false
    @State private var showImport = false
    @State private var showFileImporter = false
    @State private var showTargetEditor = false

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 12) {
            TopBar(
                onAddProxies: { showImport = true },
                onImportFile: { showFileImporter = true },
                onExport: { showExport = true },
                onSettings: { showSettings = true }
            )

            StatBar(onEditTarget: { showTargetEditor = true })

            DetailsTable()
                .panel()

            FooterBar()
        }
        .padding(14)

        .frame(minWidth: 1080, minHeight: 620)
        .background(Theme.background)
        .background(WindowCloseInterceptor())
        .onAppear {
            CloseGuard.shared.isRunning = model.isRunning
            CloseGuard.shared.resultCount = model.total
            CloseGuard.shared.onConfirm = { model.stop(silently: true) }
        }
        .onChange(of: model.isRunning) { _, running in
            CloseGuard.shared.isRunning = running
        }
        .onChange(of: model.total) { _, count in
            CloseGuard.shared.resultCount = count
        }
        .overlay {
            if showTargetEditor {
                TargetEditorCard(isPresented: $showTargetEditor)
            }
        }
        .overlay {
            if let report = model.report {
                RunReportCard(report: report) { model.report = nil }
            }
        }
        .overlay {
            if CloseGuard.shared.isPresented {
                QuitConfirmCard()
            }
        }
        .animation(.easeOut(duration: 0.16), value: CloseGuard.shared.isPresented)
        .animation(.easeOut(duration: 0.16), value: showTargetEditor)
        .animation(.easeOut(duration: 0.16), value: model.report?.id)
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .sheet(isPresented: $showExport) { ExportSheet() }
        .sheet(isPresented: $showImport) { ImportSheet() }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText, .text, .commaSeparatedText, .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.importFiles(urls)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.importFiles([url]) }
            }
        }
    }
}

private struct TopBar: View {
    @Environment(AppModel.self) private var model

    var onAddProxies: () -> Void
    var onImportFile: () -> Void
    var onExport: () -> Void
    var onSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if model.isRunning {
                Button {
                    model.stop()
                } label: {
                    StableLabel(title: "Stop",
                                systemImage: "stop.fill",
                                candidates: ["Start", "Stop"])
                }
                .buttonStyle(BarButtonStyle(prominent: true))
                .fixedSize()
            } else {
                Menu {
                    Button("Check All") { model.start() }
                    Button("Retry Failed") { model.retry([.failed, .timeout]) }
                } label: {
                    StableLabel(title: "Start",
                                systemImage: "play.fill",
                                candidates: ["Start", "Stop"])
                } primaryAction: {
                    model.start()
                }
                .menuStyle(.button)
                .buttonStyle(BarButtonStyle(prominent: true))
                .fixedSize()
            }

            Spacer(minLength: 12)

            Menu {
                Button("Paste a list…", action: onAddProxies)
                Button("Open file…", action: onImportFile)
            } label: {
                Label("Add Proxies", systemImage: "plus")
            }
            .menuStyle(.button)
            .buttonStyle(BarButtonStyle())
            .fixedSize()

            Button(action: onExport) {
                Label("Export", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(BarButtonStyle())
            .fixedSize()

            Button {
                model.showPasswords.toggle()
            } label: {

                StableLabel(
                    title: model.showPasswords ? "Hide Passwords" : "Show Passwords",
                    systemImage: model.showPasswords ? "eye.slash" : "eye",
                    candidates: ["Hide Passwords", "Show Passwords"]
                )
            }
            .buttonStyle(BarButtonStyle())
            .fixedSize()

            Button {
                model.clear()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(BarButtonStyle())
            .fixedSize()

            Button(action: onSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(BarButtonStyle())
            .fixedSize()
        }
    }
}

private struct StatBar: View {
    @Environment(AppModel.self) private var model
    var onEditTarget: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            chip(count: model.total, label: "All", color: Theme.textSecondary, filter: nil, showPercent: false)
            chip(count: model.goodCount, label: "Good", color: Theme.good, filter: .good)
            chip(count: model.slowCount, label: "Slow", color: Theme.slow, filter: .slow)
            chip(count: model.timeoutCount, label: "Timeout", color: Theme.timeout, filter: .timeout)
            chip(count: model.failedCount, label: "Failed", color: Theme.failed, filter: .failed)
            chip(count: model.notTestedCount, label: "Not Tested", color: Theme.neutral, filter: .notTested, showPercent: false)

            Spacer(minLength: 16)

            Button(action: onEditTarget) {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                    Text("Target")
                        .foregroundStyle(Theme.textSecondary)
                    Text(model.settings.targetHost)
                        .font(.mono(12))
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "pencil")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textFaint)
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize()
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Change the site every proxy is checked against")
            .padding(.trailing, 12)
        }
        .frame(height: 46)
        .panel()
    }

    private var countColumnWidth: CGFloat {
        let digits = max(1, String(model.total).count)
        return CGFloat(digits) * 8.5
    }

    private func chip(count: Int,
                      label: String,
                      color: Color,
                      filter: ProxyStatus?,
                      showPercent: Bool = true) -> some View {
        let isActive = model.statusFilter == filter && filter != nil

        return Button {
            model.statusFilter = (model.statusFilter == filter) ? nil : filter
        } label: {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(verbatim: "\(count)")
                    .font(.mono(13, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: countColumnWidth, alignment: .trailing)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                if showPercent, model.total > 0 {
                    Text(verbatim: model.percent(count))
                        .font(.mono(10, .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .frame(width: 30, alignment: .trailing)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                }
            }

            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
            .background(isActive ? Color.white.opacity(0.05) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(filter == nil ? "" : "Show only \(label.lowercased()) proxies")
    }
}

private struct FooterBar: View {
    @Environment(AppModel.self) private var model
    @FocusState private var filterFocused: Bool

    var body: some View {
        @Bindable var model = model

        HStack(spacing: 12) {
            if model.isRunning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text("Checking \(model.completedCount) of \(model.total) · \(model.settings.threads) threads · \(model.elapsedText)")
            } else if let geoStatus = model.geoStatus {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text(geoStatus)
            } else if let toast = model.toast {
                Text(toast).transition(.opacity)
            } else if model.total > 0 {
                Text("\(model.total) proxies loaded\(model.elapsedText.isEmpty ? "" : " · last run \(model.elapsedText)")")
            } else {
                Text("Drop a proxy list here, or use Add Proxies.")
            }

            Spacer()

            TextField("Filter host, country, state, ISP…", text: $model.searchText)
                .textFieldStyle(.plain)
                .focused($filterFocused)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(width: 280)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.panel)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(filterFocused ? Theme.hairlineStrong : Theme.hairline, lineWidth: 1)
                )
                .onSubmit { filterFocused = false }
                .onExitCommand { filterFocused = false }
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.textSecondary)
        .frame(height: 28)
        .animation(.easeInOut(duration: 0.2), value: model.toast)

        .onAppear { filterFocused = false }
    }
}

struct CenteredCard<Content: View>: View {
    var onDismiss: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            content
                .panel()
                .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
        }
        .transition(.opacity)
    }
}

private struct TargetEditorCard: View {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        CenteredCard(onDismiss: { isPresented = false }) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Check against")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Every proxy fetches this URL. The round trip is the reported speed.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                TextField("https://example.com", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .font(.mono(13))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panelRaised))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(isValid ? Theme.hairlineStrong : Theme.failed, lineWidth: 1)
                    )
                    .onSubmit(commit)

                HStack {
                    if !isValid {
                        Text("Needs a full URL, including http:// or https://")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.failed)
                    }
                    Spacer()
                    Button("Cancel") { isPresented = false }
                        .buttonStyle(BarButtonStyle())
                    Button("Save") { commit() }
                        .buttonStyle(BarButtonStyle(prominent: true))
                        .disabled(!isValid)
                }
            }
            .padding(22)
            .frame(width: 480)
        }
        .onAppear {
            draft = model.settings.targetURL
            focused = true
        }
        .onExitCommand { isPresented = false }
    }

    private var isValid: Bool {
        guard let url = URL(string: draft.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else { return false }
        return true
    }

    private func commit() {
        guard isValid else { return }
        model.settings.targetURL = draft.trimmingCharacters(in: .whitespaces)
        isPresented = false
    }
}

private struct RunReportCard: View {
    let report: RunReport
    var onClose: () -> Void

    var body: some View {
        CenteredCard(onDismiss: onClose) {
            VStack(spacing: 14) {
                Image(systemName: report.wasStopped ? "stop.circle" : "checkmark.circle")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(report.wasStopped ? Theme.slow : Theme.good)

                VStack(spacing: 5) {
                    Text(report.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(report.detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                    if !report.elapsed.isEmpty {
                        Text("Finished in \(report.elapsed)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textFaint)
                    }
                }

                Button("Close", action: onClose)
                    .buttonStyle(BarButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 34)
            .padding(.vertical, 26)
            .frame(width: 360)
        }
        .onExitCommand(perform: onClose)
    }
}

private struct QuitConfirmCard: View {

    var body: some View {
        let guardObject = CloseGuard.shared

        CenteredCard(onDismiss: { guardObject.cancel() }) {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.slow)

                VStack(spacing: 6) {
                    Text("Quit Rocket Proxy Checker?")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(guardObject.message)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button("Cancel") { guardObject.cancel() }
                        .buttonStyle(BarButtonStyle())
                        .keyboardShortcut(.cancelAction)

                    Button("Quit Anyway") { guardObject.confirmQuit() }
                        .buttonStyle(BarButtonStyle(prominent: true))
                }
                .padding(.top, 2)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
            .frame(width: 400)
        }
        .onExitCommand { guardObject.cancel() }
    }
}
