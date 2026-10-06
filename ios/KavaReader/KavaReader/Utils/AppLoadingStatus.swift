import SwiftUI

/// The shared loading indicator displayed in the navigation title area.
struct AppLoadingStatus: View {
    let message: String?
    var title: LocalizedStringKey? = nil

    @State private var lastMessage: String?

    private var isVisible: Bool { message != nil }

    var body: some View {
        ZStack {
            if let title {
                Text(title)
                    .font(.headline)
                    .opacity(isVisible ? 0 : 1)
                    .accessibilityHidden(isVisible)
            }

            HStack(spacing: 8) {
                ProgressView()
                Text(message ?? lastMessage ?? " ")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : -14)
            .accessibilityHidden(!isVisible)
        }
        .frame(height: 42)
        .animation(.easeOut(duration: 0.28), value: isVisible)
        .allowsHitTesting(false)
        .onChange(of: message) { _, newMessage in
            if let newMessage { lastMessage = newMessage }
        }
    }
}
