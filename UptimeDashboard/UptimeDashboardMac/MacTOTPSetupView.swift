import SwiftUI
import CoreImage.CIFilterBuiltins

struct MacTOTPSetupView: View {
    let secret: String
    let uri: String

    @EnvironmentObject var viewModel: MacAppViewModel
    @State private var code = ""

    private var isCodeValid: Bool {
        code.count == 6 && code.allSatisfy(\.isNumber)
    }

    private var qrImage: NSImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(uri.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Configura 2FA")
                .font(.title2.bold())

            Text("Scansiona il QR code con la tua app di autenticazione")
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let img = qrImage {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .cornerRadius(8)
            }

            VStack(spacing: 4) {
                Text("Oppure inserisci manualmente:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(secret)
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(Color.gray.opacity(0.15))
                    .cornerRadius(6)
                    .textSelection(.enabled)
            }

            TextField("Codice a 6 cifre", text: $code)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .multilineTextAlignment(.center)
                .onChange(of: code) { newValue in
                    let filtered = String(newValue.filter(\.isNumber).prefix(6))
                    if filtered != newValue { code = filtered }
                }

            if let error = viewModel.errorMessage {
                Text(error).foregroundColor(.red).font(.footnote)
            }

            Button {
                Task { await viewModel.enrollTOTP(code: code) }
            } label: {
                if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Verifica e attiva")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isCodeValid || viewModel.isLoading)
            .keyboardShortcut(.defaultAction)

            Spacer()
        }
        .padding()
    }
}
