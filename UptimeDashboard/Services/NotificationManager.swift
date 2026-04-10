// Feature: ios-native-app
// Requisiti: 9.1, 9.2, 9.4, 9.5, 9.6, 9.7

import Foundation
import UserNotifications
import UIKit

// MARK: - Protocol

protocol NotificationManagerProtocol {
    func requestPermission() async -> Bool
    func registerForRemoteNotifications()
    func handleTokenUpdate(deviceToken: Data) async
    func unregister() async throws
}

// MARK: - NotificationManager

final class NotificationManager: NotificationManagerProtocol {

    /// Singleton configurato da UptimeDashboardApp dopo la creazione del NetworkClient.
    static var shared: NotificationManager = NotificationManager()

    var network: NetworkClientProtocol?
    private let defaults: UserDefaults

    // UserDefaults keys — not sensitive data, just flags/hex token
    private let pendingKey = "pendingAPNsRegistration"
    private let tokenKey = "apnsDeviceToken"

    // MARK: - Init

    init(network: NetworkClientProtocol? = nil, defaults: UserDefaults = .standard) {
        self.network = network
        self.defaults = defaults
    }

    // MARK: - requestPermission

    /// Requests UNUserNotificationCenter authorization.
    /// Returns `true` if the user granted permission.
    func requestPermission() async -> Bool {
        do {
            // Richiede anche Critical Alerts se l'entitlement è approvato da Apple
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound, .criticalAlert])
            return granted
        } catch {
            // Fallback senza criticalAlert se l'entitlement non è presente
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            return granted
        }
    }

    // MARK: - registerForRemoteNotifications

    /// Registers the app with APNs on the main thread.
    func registerForRemoteNotifications() {
        Task { @MainActor in
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    // MARK: - handleTokenUpdate

    /// Converts the raw APNs device token `Data` to a hex string,
    /// persists it in UserDefaults, then subscribes with the backend.
    /// On network failure sets `pendingAPNsRegistration = true` so the
    /// app can retry on next launch (Req 9.5).
    func handleTokenUpdate(deviceToken: Data) async {
        let hexToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        defaults.set(hexToken, forKey: tokenKey)

        guard let network else {
            defaults.set(true, forKey: pendingKey)
            return
        }

        let deviceId = await MainActor.run {
            UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        }
        do {
            try await network.subscribeAPNs(deviceToken: hexToken, deviceId: deviceId)
            defaults.set(false, forKey: pendingKey)
        } catch {
            defaults.set(true, forKey: pendingKey)
        }
    }

    // MARK: - unregister

    /// Reads the stored token and unsubscribes from the backend,
    /// then removes the token from UserDefaults.
    func unregister() async throws {
        guard let hexToken = defaults.string(forKey: tokenKey) else { return }
        try await network?.unsubscribeAPNs(deviceToken: hexToken)
        defaults.removeObject(forKey: tokenKey)
    }
}
