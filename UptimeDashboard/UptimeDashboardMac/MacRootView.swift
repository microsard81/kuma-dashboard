import SwiftUI

struct MacRootView: View {
    @EnvironmentObject var viewModel: MacAppViewModel

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
    }
}
