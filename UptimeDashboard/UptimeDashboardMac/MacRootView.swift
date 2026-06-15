import SwiftUI

struct MacRootView: View {
    @EnvironmentObject var viewModel: MacAppViewModel

    private var colorScheme: ColorScheme? {
        switch viewModel.themeMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        Group {
            switch viewModel.authState {
            case .login:
                MacLoginView()
            case .biometricGate:
                MacBiometricGateView()
            case .changePassword:
                MacChangePasswordView()
            case .totpSetup(let secret, let uri):
                MacTOTPSetupView(secret: secret, uri: uri)
            case .twoFA:
                MacTwoFAView()
            case .authenticated:
                MacDashboardView()
                    .onAppear { viewModel.startAutoRefresh() }
                    .onDisappear { viewModel.stopAutoRefresh() }
            }
        }
        .preferredColorScheme(colorScheme)
        .environment(\.textScale, viewModel.textScale)
    }
}
