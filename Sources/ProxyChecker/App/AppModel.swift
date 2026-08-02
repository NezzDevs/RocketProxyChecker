import Foundation
import Observation
import AppKit

final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func cancel() {
        lock.lock(); value = true; lock.unlock()
    }
}

final class ResultSink: @unchecked Sendable {
    private let lock = NSLock()
    private var started: [UUID] = []
    private var finished: [(UUID, CheckOutcome)] = []

    func markStarted(_ id: UUID) {
        lock.lock(); started.append(id); lock.unlock()
    }

    func add(_ id: UUID, _ outcome: CheckOutcome) {
        lock.lock(); finished.append((id, outcome)); lock.unlock()
    }

    func drain() -> ([UUID], [(UUID, CheckOutcome)]) {
        lock.lock()
        let s = started, f = finished
        started.removeAll(keepingCapacity: true)
        finished.removeAll(keepingCapacity: true)
        lock.unlock()
        return (s, f)
    }
}

enum SortColumn: String, CaseIterable {
    case host, port, username, country, state, isp, type, security, speed, status
}

struct RunReport: Identifiable {
    let id = UUID()
    var good: Int
    var slow: Int
    var timeout: Int
    var failed: Int
    var elapsed: String
    var wasStopped: Bool

    var title: String { wasStopped ? "Check stopped" : "Check complete" }

    var detail: String {
        "\(good) good · \(slow) slow · \(timeout) timed out · \(failed) failed"
    }
}

@MainActor
@Observable
final class AppModel {

    var rows: [ProxyRow] = []
    var settings = CheckSettings() { didSet { persistSettings() } }
    var exportFilter = ExportFilter()

    var showPasswords = false
    var isRunning = false
    var searchText = ""
    var sortColumn: SortColumn = .speed
    var sortAscending = true
    var statusFilter: ProxyStatus?
    private(set) var toast: String?
    var report: RunReport?
    private(set) var geoStatus: String?

    var completedCount = 0
    var runStartedAt: Date?
    var elapsedText = ""

    private var indexByID: [UUID: Int] = [:]
    private var cancelFlag = CancelFlag()
    private var pumpTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var stoppedManually = false
    private let sink = ResultSink()

    init() {
        loadSettings()
    }

    func notify(_ message: String, seconds: Double = 4) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        toastTask = nil
        toast = nil
    }

    var total: Int { rows.count }
    var goodCount: Int { count(of: .good) }
    var slowCount: Int { count(of: .slow) }
    var timeoutCount: Int { count(of: .timeout) }
    var failedCount: Int { count(of: .failed) }
    var notTestedCount: Int { count(of: .notTested) + count(of: .checking) }

    private func count(of status: ProxyStatus) -> Int {
        rows.lazy.filter { $0.status == status }.count
    }

    func percent(_ n: Int) -> String {
        guard total > 0 else { return "0%" }
        return "\(Int((Double(n) / Double(total) * 100).rounded()))%"
    }

    var visibleRows: [ProxyRow] {
        var out = rows

        if let statusFilter {
            out = out.filter { $0.status == statusFilter }
        }

        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            out = out.filter { row in
                row.host.lowercased().contains(query)
                || String(row.port).contains(query)
                || (row.statusCode.map { String($0).contains(query) } ?? false)
                || (row.username?.lowercased().contains(query) ?? false)
                || (row.country?.lowercased().contains(query) ?? false)
                || (row.state?.lowercased().contains(query) ?? false)
                || (row.isp?.lowercased().contains(query) ?? false)
                || (row.exitIP?.contains(query) ?? false)
            }
        }

        let ascending = sortAscending
        out.sort { a, b in
            let result: Bool
            switch sortColumn {
            case .host: result = a.host.localizedStandardCompare(b.host) == .orderedAscending
            case .port: result = a.port < b.port
            case .username: result = (a.username ?? "") < (b.username ?? "")
            case .country: result = (a.country ?? "~") < (b.country ?? "~")
            case .state: result = (a.state ?? "~") < (b.state ?? "~")
            case .isp: result = (a.isp ?? "~") < (b.isp ?? "~")
            case .type: result = a.resolvedType.label < b.resolvedType.label
            case .security: result = a.anonymity.label < b.anonymity.label
            case .speed: result = (a.speedMs ?? Int.max) < (b.speedMs ?? Int.max)
            case .status: result = a.status.rawValue < b.status.rawValue
            }
            return ascending ? result : !result
        }
        return out
    }

    var availableCountries: [String] {
        Array(Set(rows.compactMap(\.country))).sorted()
    }

    var availableStates: [String] {
        Array(Set(rows.compactMap(\.state))).sorted()
    }

    func importText(_ text: String) {
        let parsed = ProxyParser.parse(text)
        guard !parsed.rows.isEmpty else {
            notify("No valid proxies found in that text.")
            return
        }
        var existing = Set(rows.map { "\($0.host.lowercased()):\($0.port):\($0.username ?? "")" })
        var added = 0
        for row in parsed.rows {
            let key = "\(row.host.lowercased()):\(row.port):\(row.username ?? "")"
            if existing.contains(key) { continue }
            existing.insert(key)
            rows.append(row)
            added += 1
        }
        rebuildIndex()
        var message = "Added \(added) proxies."
        if parsed.skipped > 0 { message += " Skipped \(parsed.skipped) unreadable lines." }
        notify(message)
    }

    func importFiles(_ urls: [URL]) {
        var combined = ""
        for url in urls {
            let needsScope = url.startAccessingSecurityScopedResource()
            defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                combined += text + "\n"
            } else if let data = try? Data(contentsOf: url) {
                combined += String(decoding: data, as: UTF8.self) + "\n"
            }
        }
        importText(combined)
    }

    func clear() {
        stop(silently: true)
        rows.removeAll()
        indexByID.removeAll()
        completedCount = 0
        elapsedText = ""
        report = nil
        dismissToast()
    }

    private func rebuildIndex() {
        indexByID = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
    }

    func start(only subset: [ProxyRow]? = nil) {
        guard !isRunning else { return }
        let targets = subset ?? rows
        guard !targets.isEmpty else {
            notify("Import a proxy list first.")
            return
        }

        rebuildIndex()
        cancelFlag = CancelFlag()
        isRunning = true
        stoppedManually = false
        completedCount = 0
        runStartedAt = Date()
        report = nil
        dismissToast()

        let targetIDs = Set(targets.map(\.id))
        for i in rows.indices where targetIDs.contains(rows[i].id) {
            rows[i].status = .notTested
            rows[i].speedMs = nil
            rows[i].statusCode = nil
            rows[i].supportedTypes = rows[i].declaredType.map { [$0] } ?? []
            rows[i].error = nil
        }

        startPump()

        let settings = self.settings
        let flag = cancelFlag
        let sink = self.sink

        Task.detached(priority: .userInitiated) {
            let realIP = settings.detectAnonymity ? await ProxyCheckEngine.fetchRealIP() : nil
            await ProxyCheckEngine.run(
                rows: targets,
                settings: settings,
                realIP: realIP,
                isCancelled: { flag.isCancelled },
                onStart: { sink.markStarted($0) },
                onResult: { sink.add($0, $1) }
            )
            await MainActor.run { [weak self] in
                self?.finishRun()
            }
        }
    }

    func retry(_ statuses: Set<ProxyStatus>) {
        let subset = rows.filter { statuses.contains($0.status) }
        guard !subset.isEmpty else {
            notify("Nothing to retry.")
            return
        }
        start(only: subset)
    }

    func stop(silently: Bool = false) {
        guard isRunning else { return }
        stoppedManually = !silently
        cancelFlag.cancel()
        pumpTask?.cancel()
        pumpTask = nil
        flush()
        for i in rows.indices where rows[i].status == .checking {
            rows[i].status = .notTested
        }
        isRunning = false
        if !silently {
            Task { [weak self] in
                await self?.resolveGeo()
                self?.presentReport()
            }
        }
    }

    private func finishRun() {
        guard isRunning else { return }
        flush()
        isRunning = false
        pumpTask?.cancel()
        pumpTask = nil
        if let started = runStartedAt {
            elapsedText = formatDuration(Date().timeIntervalSince(started))
        }
        Task { [weak self] in
            await self?.resolveGeo()
            self?.presentReport()
        }
    }

    private func resolveGeo() async {
        guard settings.lookupGeo else { return }

        let live = rows.filter { $0.status == .good || $0.status == .slow }
        guard !live.isEmpty else { return }

        var ipByRow: [UUID: String] = [:]

        switch settings.geoSource {
        case .exitIP:
            for row in live {
                if let ip = row.exitIP, !ip.isEmpty { ipByRow[row.id] = ip }
            }
        case .proxyHost:
            geoStatus = "Resolving addresses…"
            var byHost: [String: String] = [:]
            for host in Set(live.map(\.host)) {
                if let ip = await GeoService.shared.resolveHost(host) { byHost[host] = ip }
            }
            for row in live {
                if let ip = byHost[row.host] { ipByRow[row.id] = ip }
            }
        }

        let uniqueIPs = Array(Set(ipByRow.values))
        guard !uniqueIPs.isEmpty else {
            geoStatus = nil
            return
        }

        geoStatus = "Resolving locations… 0 of \(uniqueIPs.count)"
        let geo = await GeoService.shared.lookup(ips: uniqueIPs) { [weak self] done, total in
            Task { @MainActor in
                self?.geoStatus = "Resolving locations… \(done) of \(total)"
            }
        }

        rebuildIndex()
        for (rowID, ip) in ipByRow {
            guard let i = indexByID[rowID] else { continue }
            rows[i].exitIP = ip
            guard let info = geo[ip] else { continue }
            rows[i].country = info.country
            rows[i].countryCode = info.countryCode
            rows[i].state = info.regionName
            rows[i].isp = info.isp
        }

        geoStatus = nil
    }

    func clearGeoCache() {
        Task {
            await GeoService.shared.clearCache()
            notify("Location cache cleared.")
        }
    }

    func toggleSort(_ column: SortColumn) {
        if sortColumn == column {
            if sortAscending {
                sortAscending = false
            } else {
                sortColumn = .speed
                sortAscending = true
            }
        } else {
            sortColumn = column
            sortAscending = true
        }
    }

    private func presentReport() {

        sortColumn = .speed
        sortAscending = true

        if let started = runStartedAt {
            elapsedText = formatDuration(Date().timeIntervalSince(started))
        }
        report = RunReport(
            good: goodCount,
            slow: slowCount,
            timeout: timeoutCount,
            failed: failedCount,
            elapsed: elapsedText,
            wasStopped: stoppedManually
        )
    }

    private func startPump() {
        pumpTask?.cancel()
        pumpTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard let self else { return }
                self.flush()
                if let started = self.runStartedAt, self.isRunning {
                    self.elapsedText = formatDuration(Date().timeIntervalSince(started))
                }
            }
        }
    }

    private func flush() {
        let (started, finished) = sink.drain()
        guard !started.isEmpty || !finished.isEmpty else { return }

        for id in started {
            guard let i = indexByID[id] else { continue }
            if rows[i].status == .notTested { rows[i].status = .checking }
        }

        for (id, outcome) in finished {
            guard let i = indexByID[id] else { continue }
            rows[i].status = outcome.status
            rows[i].speedMs = outcome.speedMs
            rows[i].statusCode = outcome.statusCode
            rows[i].resolvedType = outcome.type
            rows[i].supportedTypes = outcome.supportedTypes
            rows[i].exitIP = outcome.exitIP
            rows[i].country = outcome.country
            rows[i].countryCode = outcome.countryCode
            rows[i].state = outcome.state
            rows[i].isp = outcome.isp
            rows[i].anonymity = outcome.anonymity
            rows[i].error = outcome.error
            rows[i].checkedAt = Date()
            completedCount += 1
        }
    }

    func export(format: ExportFormat, grouping: ExportGrouping) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export here"
        panel.message = "Choose a folder for the exported proxy files."

        guard panel.runModal() == .OK, let directory = panel.url else { return }

        do {
            let summary = try Exporter.export(rows: rows,
                                              filter: exportFilter,
                                              format: format,
                                              grouping: grouping,
                                              to: directory)
            if summary.proxyCount == 0 {
                notify("No proxies matched the export filter.")
            } else {
                notify("Exported \(summary.proxyCount) proxies to \(summary.fileCount) file\(summary.fileCount == 1 ? "" : "s").")
                NSWorkspace.shared.activateFileViewerSelecting([directory])
            }
        } catch {
            notify("Export failed: \(error.localizedDescription)")
        }
    }

    func copyToClipboard(format: ExportFormat) {
        let matching = rows.filter { exportFilter.matches($0) }
        guard !matching.isEmpty else {
            notify("No proxies matched the export filter.")
            return
        }
        let text = Exporter.render(rows: matching, format: format)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        notify("Copied \(matching.count) proxies.")
    }

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "CheckSettings")
        }
    }

    private func loadSettings() {
        guard let data = UserDefaults.standard.data(forKey: "CheckSettings"),
              var decoded = try? JSONDecoder().decode(CheckSettings.self, from: data) else { return }
        if CheckSettings.supersededTargets.contains(decoded.targetURL) {
            decoded.targetURL = CheckSettings().targetURL
        }
        settings = decoded
    }
}

func formatDuration(_ interval: TimeInterval) -> String {
    let seconds = Int(interval)
    if seconds < 60 { return "\(seconds)s" }
    return "\(seconds / 60)m \(seconds % 60)s"
}
