//
//  Rocket Proxy Checker — a native proxy checker for macOS.
//  Copyright (C) 2026 NezzDevs
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        raiseFileDescriptorLimit()
    }

    private func raiseFileDescriptorLimit() {
        var limit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return }
        limit.rlim_cur = min(rlim_t(16384), limit.rlim_max)
        setrlimit(RLIMIT_NOFILE, &limit)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ProxyCheckerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Rocket Proxy Checker", id: "main") {
            ContentView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.textPrimary)
        }
        .defaultSize(width: Columns.windowWidth, height: 900)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandMenu("Check") {
                Button("Check All") { model.start() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Retry Failed") { model.retry([.failed, .timeout]) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Divider()
                Button("Stop") { model.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                Divider()
                Button("Clear List") { model.clear() }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }
        }
    }
}
