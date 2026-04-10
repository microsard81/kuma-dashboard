// Feature: ios-native-app
// Requisiti: 1.5, 9.5, 9.6, 9.7, 11.1, 11.2

import SwiftUI
import UserNotifications

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task {
            await NotificationManager.shared.handleTokenUpdate(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        UserDefaults.standard.set(true, forKey: "pendingAPNsRegistration")
        print("[AppDelegate] WARNING: APNs registration failed — \(error.localizedDescription)")
    }
}

// MARK: - UptimeDashboardApp

@main
struct UptimeDashboardApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    private let network: NetworkClientProtocol
    @StateObject private var authViewModel: AuthViewModel
    @StateObject private var dashboardViewModel: DashboardViewModel
    @StateObject private var settingsViewModel: SettingsViewModel
    @State private var showSplash = true

    init() {
        let client: NetworkClientProtocol = {
            guard let c = try? NetworkClient() else {
                fatalError("NetworkClient: BACKEND_BASE_URL deve usare https://")
            }
            return c
        }()

        network = client
        NotificationManager.shared.network = client

        _authViewModel = StateObject(wrappedValue: AuthViewModel(
            network: client,
            keychain: KeychainStore.shared
        ))
        _dashboardViewModel = StateObject(wrappedValue: DashboardViewModel(network: client))
        _settingsViewModel = StateObject(wrappedValue: SettingsViewModel(
            notificationManager: NotificationManager.shared,
            network: client
        ))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                rootView
                    .preferredColorScheme(settingsViewModel.themeMode.colorScheme)
                    .environmentObject(authViewModel)
                    .environmentObject(settingsViewModel)
                    .task { await retryPendingAPNsIfNeeded() }
                    .onChange(of: authViewModel.state) { newState in
                        if newState == .authenticated {
                            Task { await requestNotificationsIfNeeded() }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
                        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                    }

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                        .task {
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            withAnimation(.easeOut(duration: 0.4)) {
                                showSplash = false
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch authViewModel.state {
        case .idle:
            if settingsViewModel.biometricEnabled {
                BiometricGateView()
                    .environmentObject(authViewModel)
            } else {
                LoginView()
            }
        case .authenticated:
            DashboardView(network: network)
        case .requires2FA:
            TwoFAView()
        case .requiresPasswordChange:
            ChangePasswordView()
        case .requiresTOTPSetup(let secret, let uri):
            TOTPSetupView(secret: secret, uri: uri)
        default:
            LoginView()
        }
    }

    private func requestNotificationsIfNeeded() async {
        let granted = await NotificationManager.shared.requestPermission()
        if granted {
            NotificationManager.shared.registerForRemoteNotifications()
        }
    }

    private func retryPendingAPNsIfNeeded() async {
        guard UserDefaults.standard.bool(forKey: "pendingAPNsRegistration") else { return }
        NotificationManager.shared.registerForRemoteNotifications()
    }
}
