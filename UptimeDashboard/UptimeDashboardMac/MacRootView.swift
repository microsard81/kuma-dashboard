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
        .environment(\.sizeCategory, sizeCategory)
    }

    private var sizeCategory: ContentSizeCategory {
        switch viewModel.textScale {
        case ..<0.9: return .small
        case 0.9..<1.1: return .medium
        case 1.1..<1.3: return .large
        case 1.3..<1.5: return .extraLarge
        default: return .extraExtraLarge
        }
    }
}
