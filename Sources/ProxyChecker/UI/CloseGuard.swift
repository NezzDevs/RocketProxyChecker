import SwiftUI
import AppKit
import Observation

@MainActor
@Observable
final class CloseGuard {

    static let shared = CloseGuard()

    var isPresented = false
    var isRunning = false
    var resultCount = 0

    @ObservationIgnored var onConfirm: () -> Void = {}
    @ObservationIgnored private(set) var confirmed = false

    private init() {}

    var needsPrompt: Bool {
        !confirmed && (isRunning || resultCount > 0)
    }

    var message: String {
        if isRunning {
            return resultCount > 0
                ? "A check is still running. Quitting now discards the run and all \(resultCount) results."
                : "A check is still running. Quitting now discards it."
        }
        return "Quitting now discards all \(resultCount) results. Export them first if you want to keep them."
    }

    func present() {
        isPresented = true
    }

    func cancel() {
        isPresented = false
    }

    func confirmQuit() {
        confirmed = true
        isPresented = false
        onConfirm()
        NSApp.terminate(nil)
    }
}

final class WindowCloseGuard: NSObject, NSWindowDelegate {

    weak var previous: NSWindowDelegate?

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return previous?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if super.responds(to: aSelector) { return nil }
        return previous
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let guardObject = CloseGuard.shared
        if guardObject.needsPrompt {
            guardObject.present()
            return false
        }
        return true
    }
}

struct WindowCloseInterceptor: NSViewRepresentable {

    func makeCoordinator() -> WindowCloseGuard { WindowCloseGuard() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let coordinator = context.coordinator
            guard window.delegate !== coordinator else { return }
            coordinator.previous = window.delegate
            window.delegate = coordinator
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
