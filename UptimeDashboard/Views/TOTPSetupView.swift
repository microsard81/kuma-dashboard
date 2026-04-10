import SwiftUI
import CoreImage.CIFilterBuiltins

struct TOTPSetupView: View {

    let secret: String
    let uri: String

    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var code: String = ""

    private var isCodeValid: Bool {
        code.count == 6 && code.allSatisfy(\.isNumber)
    }

    /// Genera un QR code dall'URI TOTP.
    private var qrImage: UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(uri.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#141c2b")
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        Spacer().frame(height: 20)

                        Text("Configura 2FA")
                            .font(.title2.bold())
                            .accessibilityAddTraits(.isHeader)

                        Text("Scansiona il QR code con la tua app di autenticazione (Google Authenticator, Authy, ecc.)")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        // QR Code
                        if let img = qrImage {
                            Image(uiImage: img)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 200, height: 200)
                                .cornerRadius(12)
                                .padding(12)
                                .background(Color.white)
                                .cornerRadius(16)
                        }

                        // Secret manuale
                        VStack(spacing: 4) {
                            Text("Oppure inserisci manualmente:")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                            Text(secret)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                                .textSelection(.enabled)
                        }

                        // Code input
                        TextField("Codice a 6 cifre", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .multilineTextAlignment(.center)
                            .font(.title.monospacedDigit())
                            .padding()
                            .foregroundColor(.primary)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(10)
                            .padding(.horizontal)
                            .onChange(of: code) { newValue in
                                let filtered = String(newValue.filter(\.isNumber).prefix(6))
                                if filtered != newValue { code = filtered }
                            }

                        if let error = authViewModel.errorMessage {
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.footnote)
                        }

                        Button {
                            Task { await authViewModel.enrollTOTP(code: code) }
                        } label: {
                            Group {
                                if authViewModel.isLoading {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("Verifica e attiva").fontWeight(.semibold)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isCodeValid ? Color.accentColor : Color.gray)
                            .foregroundStyle(.white)
                            .cornerRadius(10)
                        }
                        .disabled(!isCodeValid || authViewModel.isLoading)
                        .padding(.horizontal)

                        Spacer()
                    }
                }
                .foregroundStyle(.white)
            }
            .navigationBarHidden(true)
        }
    }
}
