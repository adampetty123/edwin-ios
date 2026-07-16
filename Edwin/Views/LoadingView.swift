import SwiftUI

/// Branded loading screen shown while the app boots (session restore, first
/// data load). Edwin's avatar breathing on the warm background — matches the
/// launch screen so open feels like one continuous moment, not a white flash.
struct LoadingView: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                Image("EdwinAvatar")
                    .resizable().scaledToFill()
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
                    .scaleEffect(pulse ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
                Text("Edwin")
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text("getting your day in order…")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .onAppear { pulse = true }
    }
}
