import os
import SwiftUI
import UserNotifications

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
                    NSApp.windows.first?.delegate = appDelegate
                    appDelegate.viewModel = viewModel
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    // Azzera il badge APNs quando l'app torna in primo piano
                    UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 650)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Aggiorna Dashboard") {
                    Task { await viewModel.fetchDashboard() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            // Sostituisci il menu Help con la nostra documentazione
            CommandGroup(replacing: .help) {
                Button("Aiuto Dashboard INVA MAC") {
                    showHelpWindow()
                }
            }
        }

        Settings {
            MacSettingsView()
                .environmentObject(viewModel)
        }

        // Menu bar icon con stato globale
        MenuBarExtra {
            MenuBarView()
                .environmentObject(viewModel)
        } label: {
            HStack(spacing: 4) {
                Image("MenuBarIcon")
                    .renderingMode(.template)
                Circle()
                    .fill(menuBarLedColor)
                    .frame(width: 8, height: 8)
            }
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarLedColor: Color {
        switch viewModel.globalState {
        case "RED": return .red
        case "YELLOW": return .yellow
        default: return .green
        }
    }

    private func showHelpWindow() {
        let windowId = "help-window"
        // Cerca se la finestra help è già aperta
        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue == windowId }) {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let helpView = NSHostingController(rootView: MacHelpView())
        let window = NSWindow(contentViewController: helpView)
        window.identifier = NSUserInterfaceItemIdentifier(windowId)
        window.title = "Aiuto Dashboard INVA MAC"
        window.setContentSize(NSSize(width: 650, height: 700))
        window.styleMask = [.titled, .closable, .resizable]
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - AppDelegate

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "UptimeDashboardMac", category: "APNs")

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    weak var viewModel: MacAppViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Nasconde la finestra invece di chiuderla — l'app resta nella menu bar
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)  // Rimuove l'icona dal Dock
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // ⌘Q nasconde la finestra invece di chiudere l'app
        for window in NSApp.windows {
            if window.isVisible && window.identifier?.rawValue != "help-window" {
                window.orderOut(nil)
            }
        }
        NSApp.setActivationPolicy(.accessory)
        return .terminateCancel
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Riporta l'icona nel Dock e mostra la finestra
        NSApp.setActivationPolicy(.regular)
        if !flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // MARK: - Push Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                logger.error("[Mac] Notification authorization error: \(error.localizedDescription, privacy: .public)")
            }
            if granted {
                logger.info("[Mac] Notification permission granted — registering for remote notifications")
                DispatchQueue.main.async {
                    NSApplication.shared.registerForRemoteNotifications()
                }
            } else {
                logger.warning("[Mac] Notification permission denied by user")
            }
        }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        logger.info("[Mac] APNs device token received: \(token.prefix(16), privacy: .public)...")
        UserDefaults.standard.set(token, forKey: "mac_apnsDeviceToken")
        Task {
            await registerTokenWithBackend(token: token)
        }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        logger.error("[Mac] APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    // Mostra notifiche anche quando l'app è in primo piano
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let content = notification.request.content
        let requestId = notification.request.identifier
        NotificationStore.shared.save(title: content.title, body: content.body, requestId: requestId)
        completionHandler([.banner, .sound, .badge])
    }

    // Quando l'utente clicca la notifica — salva se non già presente
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let content = response.notification.request.content
        let requestId = response.notification.request.identifier
        NotificationStore.shared.save(title: content.title, body: content.body, requestId: requestId)
        Task {
            await viewModel?.fetchDashboard()
        }
        completionHandler()
    }

    private func registerTokenWithBackend(token: String) async {
        let baseURL = "https://kuma-dashboard.sundata.cloud"
        guard let url = URL(string: "\(baseURL)/push/apns/subscribe") else { return }

        // Usa il WATCH_API_TOKEN per autenticarsi (endpoint protetto da login)
        // Per macOS, usiamo un endpoint dedicato che accetta il token API
        guard let apiURL = URL(string: "\(baseURL)/api/mac/apns/subscribe") else {
            logger.error("[Mac] Failed to construct API URL from base: \(baseURL, privacy: .public)")
            return
        }

        guard let apiToken = Bundle.main.object(forInfoDictionaryKey: "WATCH_API_TOKEN") as? String else {
            logger.warning("[Mac] WATCH_API_TOKEN not configured in Info.plist — APNs registration skipped")
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiToken, forHTTPHeaderField: "X-Watch-Token")

        let deviceId = Host.current().localizedName ?? "Mac"

        #if DEBUG
        let apnsEnvironment = "development"
        #else
        let apnsEnvironment = "production"
        #endif

        // Includi la soglia notifica corrente (salvata in UserDefaults)
        let threshold = UserDefaults.standard.object(forKey: "mac_notification_threshold") as? Int ?? 1

        let payload: [String: Any] = [
            "device_token": token,
            "device_id": deviceId,
            "environment": apnsEnvironment,
            "bundle_id": Bundle.main.bundleIdentifier ?? "",
            "threshold": threshold,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        let maxRetries = 3
        let retryDelays: [UInt64] = [1, 2, 4]

        for attempt in 1...maxRetries {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse {
                    if (200...299).contains(http.statusCode) {
                        logger.info("[Mac] APNs subscribe succeeded (attempt \(attempt)) — status: \(http.statusCode)")
                        return
                    }
                    logger.warning("[Mac] APNs subscribe non-2xx status: \(http.statusCode) (attempt \(attempt)/\(maxRetries))")
                }
            } catch {
                logger.error("[Mac] APNs subscribe error (attempt \(attempt)/\(maxRetries)): \(error.localizedDescription, privacy: .public)")
            }

            if attempt < maxRetries {
                let delay = retryDelays[attempt - 1]
                logger.info("[Mac] Retrying APNs subscribe in \(delay)s (attempt \(attempt + 1)/\(maxRetries))")
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
        }

        logger.error("[Mac] APNs subscribe failed after \(maxRetries) attempts")
    }
}
