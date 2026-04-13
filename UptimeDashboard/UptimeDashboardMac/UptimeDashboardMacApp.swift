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
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 650)

        Settings {
            MacSettingsView()
                .environmentObject(viewModel)
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, UNUserNotificationCenterDelegate {
    weak var viewModel: MacAppViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        requestNotificationPermission()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.miniaturize(nil)
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // MARK: - Push Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    NSApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[Mac] APNs token: \(token.prefix(16))...")
        Task {
            await registerTokenWithBackend(token: token)
        }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[Mac] APNs registration failed: \(error.localizedDescription)")
    }

    // Mostra notifiche anche quando l'app è in primo piano
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // Quando l'utente clicca la notifica, aggiorna la dashboard
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
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
        guard let apiURL = URL(string: "\(baseURL)/api/mac/apns/subscribe"),
              let apiToken = Bundle.main.object(forInfoDictionaryKey: "WATCH_API_TOKEN") as? String else { return }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiToken, forHTTPHeaderField: "X-Watch-Token")

        let deviceId = Host.current().localizedName ?? "Mac"
        let payload: [String: String] = [
            "device_token": token,
            "device_id": deviceId,
            "environment": "production",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                print("[Mac] APNs subscribe status: \(http.statusCode)")
            }
        } catch {
            print("[Mac] APNs subscribe error: \(error.localizedDescription)")
        }
    }
}
