// Feature: native-apps-sensor-integration

import SwiftUI

/// A full-screen overlay showing a large checkmark or X that fades in and out.
/// Used to confirm an action (e.g., pinning/unpinning a resource).
struct CheckmarkPopup: View {
    @Binding var isPresented: Bool
    var isRemoval: Bool = false

    var body: some View {
        if isPresented {
            ZStack {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    Image(systemName: isRemoval ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(isRemoval ? .red : .green)
                    Text(isRemoval ? "Rimosso" : "Aggiunto")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(30)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            }
            .transition(.opacity)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation { isPresented = false }
                }
            }
        }
    }
}
