import SwiftUI

// Keep system safe-area insets outside the comic's hosting boundary.
// Reader controls remain in the outer SwiftUI hierarchy and respect those insets.
struct ReaderCanvasHost<Content: View>: UIViewControllerRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let controller = UIHostingController(rootView: content)
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ controller: UIHostingController<Content>, context: Context) {
        // Update the existing host so toggling controls preserves page and zoom state.
        controller.rootView = content
    }
}

struct FullScreenBackground: View {
    var body: some View {
        AppTheme.background
            .ignoresSafeArea(.all)
    }
}
