import SwiftUI

@main
struct UptimeDashboardMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = MacAppViewModel()

    var body: some Scene {
        WindowGroup {
            MacRootView()
                .environmentObject(viewModel)
                .frame(minWidth: 700, minHeight: 500)
                .onAppear {
                    // Impedisci la chiusura della finestra — minimizza nel Dock
                    NSApp.windows.first?.delegate = appDelegate
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 650)
    }
}

// MARK: - AppDelegate — intercetta la chiusura della finestra

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Minimizza nel Dock invece di chiudere
        sender.miniaturize(nil)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Riapri la finestra dal Dock
        if !flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
