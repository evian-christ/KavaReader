import SwiftUI
import UIKit

/// Enlarges the complete native tab bar, including its glass capsule and hit regions.
/// The scale is modest so its floating capsule still fits narrow iPhone windows.
struct NativeTabBarScaleView<Selection: Hashable>: UIViewRepresentable {
    let scale: CGFloat
    let selection: Selection
    var backdropHeightMultiplier: CGFloat = 1

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.isUserInteractionEnabled = false
        view.scale = scale
        view.backdropHeightMultiplier = backdropHeightMultiplier
        return view
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.scale = scale
        view.backdropHeightMultiplier = backdropHeightMultiplier
        view.scheduleUpdate()
    }

    static func dismantleUIView(_ view: ObserverView, coordinator: ()) {
        view.removeBackdrop()
        view.tabBar?.transform = .identity
    }

    final class ObserverView: UIView {
        var scale: CGFloat = 1.08
        var backdropHeightMultiplier: CGFloat = 1
        weak var tabBar: UITabBar?
        private var updateScheduled = false
        private let backdrop = TabBarBackdropView(frame: .zero)
        private var originalClipsToBounds: Bool?

        func removeBackdrop() {
            backdrop.removeFromSuperview()
            if let originalClipsToBounds { tabBar?.clipsToBounds = originalClipsToBounds }
            originalClipsToBounds = nil
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            scheduleUpdate()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            scheduleUpdate()
        }

        func scheduleUpdate() {
            guard !updateScheduled else { return }
            updateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.updateScheduled = false
                self.updateBar()
            }
        }

        private func updateBar() {
            guard let root = window?.rootViewController,
                  let controller = findTabController(in: root)
            else { return }
            let bar = controller.tabBar
            if tabBar !== bar {
                removeBackdrop()
                tabBar?.transform = .identity
                tabBar = bar
            }
            guard bar.bounds.height > 0 else { return }
            if backdrop.superview !== bar {
                originalClipsToBounds = bar.clipsToBounds
                bar.clipsToBounds = false
                // A noninteractive child follows the native bar's visibility and motion,
                // including hiding in the reader. Glass is rendered above this backdrop.
                bar.insertSubview(backdrop, at: 0)
            }
            let backdropHeight = (bar.bounds.height + 88) * 0.375 * backdropHeightMultiplier
            backdrop.frame = CGRect(x: 0, y: bar.bounds.maxY - backdropHeight,
                                    width: bar.bounds.width, height: backdropHeight)
            backdrop.autoresizingMask = [.flexibleWidth, .flexibleTopMargin]
            // Grow upward from the original bottom edge, keeping the home indicator clear.
            let translation = -bar.bounds.height * (scale - 1) / 2
            let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                              tx: 0, ty: translation)
            if bar.transform != transform {
                bar.transform = transform
            }
        }

        private func findTabController(in controller: UIViewController) -> UITabBarController? {
            if let controller = controller as? UITabBarController { return controller }
            for child in controller.children {
                if let match = findTabController(in: child) { return match }
            }
            return nil
        }
    }

    final class TabBarBackdropView: UIView {
        override class var layerClass: AnyClass { CAGradientLayer.self }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            accessibilityElementsHidden = true
            backgroundColor = .clear
            guard let gradient = layer as? CAGradientLayer else { return }
            let color = UIColor(AppTheme.background)
            gradient.colors = [color.withAlphaComponent(0).cgColor,
                               color.withAlphaComponent(0.08).cgColor,
                               color.withAlphaComponent(0.277).cgColor,
                               color.withAlphaComponent(0.40).cgColor]
            gradient.locations = [0, 0.3, 0.65, 1]
            gradient.startPoint = CGPoint(x: 0.5, y: 0)
            gradient.endPoint = CGPoint(x: 0.5, y: 1)
        }

        required init?(coder: NSCoder) { nil }
    }
}
