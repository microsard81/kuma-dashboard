import SwiftUI

struct SplashView: View {

    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.85

    var body: some View {
        ZStack {
            Color(hex: "#141c2b")
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 260)
            }
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    opacity = 1
                    scale = 1
                }
            }
        }
    }
}
