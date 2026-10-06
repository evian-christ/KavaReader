import SwiftUI
import UIKit

/// Uses interactive paper curl or standard horizontal scrolling based on settings.
/// Only a completed turn changes reading progress.
struct ReaderHorizontalPager<Content: View>: UIViewControllerRepresentable {
    let size: CGSize
    let pageIDs: [Int]
    @Binding var selection: Int?
    let isZoomed: Bool
    let isDoublePage: Bool
    let pageCurlEnabled: Bool
    let content: (Int, Int?) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(size: CGSize, pageIDs: [Int], selection: Binding<Int?>, isZoomed: Bool,
         isDoublePage: Bool = false, pageCurlEnabled: Bool = true,
         @ViewBuilder content: @escaping (Int, Int?) -> Content)
    {
        self.size = size
        self.pageIDs = pageIDs
        _selection = selection
        self.isZoomed = isZoomed
        self.isDoublePage = isDoublePage
        self.pageCurlEnabled = pageCurlEnabled
        self.content = content
    }

    var usesBookFaces: Bool { pageCurlEnabled && isDoublePage }
    var spineLocation: UIPageViewController.SpineLocation { usesBookFaces ? .mid : .min }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let options: [UIPageViewController.OptionsKey: Any]? = pageCurlEnabled
            ? [.spineLocation: spineLocation.rawValue] : nil
        let controller = UIPageViewController(transitionStyle: pageCurlEnabled ? .pageCurl : .scroll,
                                              navigationOrientation: .horizontal,
                                              options: options)
        controller.isDoubleSided = usesBookFaces
        controller.preferredContentSize = size
        controller.view.backgroundColor = UIColor(AppTheme.background)
        controller.view.clipsToBounds = true
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        context.coordinator.controller = controller
        context.coordinator.synchronize(animated: false)
        return controller
    }

    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
        controller.preferredContentSize = size
        context.coordinator.parent = self
        context.coordinator.synchronize(animated: !reduceMotion)
    }

    static func dismantleUIViewController(_ controller: UIPageViewController, coordinator: Coordinator) {
        coordinator.isActive = false
        controller.delegate = nil
        controller.dataSource = nil
        coordinator.hosts.removeAll()
    }

    /// Each half of a spread is a separate face of the physical sheet.
    struct PageKey: Hashable {
        let pageID: Int
        let side: Int
    }

    final class PageHost: UIHostingController<Content> {
        let key: PageKey
        var pageID: Int { key.pageID }

        init(key: PageKey, content: Content) {
            self.key = key
            super.init(rootView: content)
            // Controls may change status-bar insets; paper always fills the canvas.
            safeAreaRegions = []
            view.backgroundColor = UIColor(AppTheme.background)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: ReaderHorizontalPager
        weak var controller: UIPageViewController?
        var hosts: [PageKey: PageHost] = [:]
        var isActive = true
        private var isTransitioning = false
        private var selectionAtGestureStart: Int?

        init(parent: ReaderHorizontalPager) { self.parent = parent }

        func synchronize(animated: Bool) {
            guard isActive, !isTransitioning, let controller else { return }
            for gesture in controller.gestureRecognizers {
                // Our image tap regions own navigation and the UI toggle.
                gesture.isEnabled = !(gesture is UITapGestureRecognizer) && !parent.isZoomed
            }
            for scrollView in controller.view.subviews.compactMap({ $0 as? UIScrollView }) {
                scrollView.isScrollEnabled = !parent.isZoomed
            }
            guard let requested = parent.selection ?? parent.pageIDs.first,
                  let targetIndex = parent.pageIDs.firstIndex(of: requested) else { return }
            let current = controller.viewControllers?.first as? PageHost
            refreshHosts(around: targetIndex)
            let targetKeys = keys(for: requested)
            let visibleKeys = controller.viewControllers?.compactMap { ($0 as? PageHost)?.key } ?? []
            guard visibleKeys != targetKeys else { return }
            let oldIndex = current.flatMap { parent.pageIDs.firstIndex(of: $0.pageID) }
            let direction: UIPageViewController.NavigationDirection = (oldIndex ?? targetIndex) > targetIndex
                ? .reverse : .forward
            isTransitioning = true
            controller.setViewControllers(targetKeys.map { host(for: $0) }, direction: direction,
                                          animated: animated && current != nil)
            { [weak self] _ in
                guard let self, self.isActive else { return }
                self.isTransitioning = false
                // A strip selection or layout update may arrive during the curl.
                self.synchronize(animated: !self.parent.reduceMotion)
            }
        }

        private func keys(for pageID: Int) -> [PageKey] {
            (0 ..< (parent.usesBookFaces ? 2 : 1)).map { PageKey(pageID: pageID, side: $0) }
        }

        private func pageContent(for key: PageKey) -> Content {
            parent.content(key.pageID, parent.usesBookFaces ? key.side : nil)
        }

        private func host(for key: PageKey) -> PageHost {
            if let cached = hosts[key] { return cached }
            let host = PageHost(key: key, content: pageContent(for: key))
            hosts[key] = host
            return host
        }

        private func refreshHosts(around index: Int) {
            let nearby = Set(parent.pageIDs[max(0, index - 1) ... min(parent.pageIDs.count - 1, index + 1)]
                .flatMap { keys(for: $0) })
            hosts = hosts.filter { nearby.contains($0.key) }
            for key in nearby {
                host(for: key).rootView = pageContent(for: key)
            }
        }

        private func adjacent(to viewController: UIViewController, offset: Int) -> UIViewController? {
            guard !parent.isZoomed,
                  let page = viewController as? PageHost,
                  let index = parent.pageIDs.firstIndex(of: page.pageID) else { return nil }
            let facesPerSpread = parent.usesBookFaces ? 2 : 1
            let nextFace = index * facesPerSpread + page.key.side + offset
            guard (0 ..< parent.pageIDs.count * facesPerSpread).contains(nextFace) else { return nil }
            return host(for: PageKey(pageID: parent.pageIDs[nextFace / facesPerSpread],
                                     side: nextFace % facesPerSpread))
        }

        func pageViewController(_: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController?
        {
            adjacent(to: viewController, offset: -1)
        }

        func pageViewController(_: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController?
        {
            adjacent(to: viewController, offset: 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                spineLocationFor _: UIInterfaceOrientation) -> UIPageViewController.SpineLocation
        {
            // Keep the selected display mode in either device orientation.
            // A middle spine curls only the outgoing half, showing the next
            // page on its reverse while the opposite half remains stationary.
            pageViewController.isDoubleSided = parent.usesBookFaces
            return parent.spineLocation
        }

        func pageViewController(_: UIPageViewController,
                                willTransitionTo _: [UIViewController])
        {
            selectionAtGestureStart = parent.selection
            isTransitioning = true
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating _: Bool,
                                previousViewControllers _: [UIViewController], transitionCompleted completed: Bool)
        {
            isTransitioning = false
            // Preserve a newer explicit selection made while a finger was down.
            if completed, parent.selection == selectionAtGestureStart,
               let page = pageViewController.viewControllers?.first as? PageHost
            {
                parent.selection = page.pageID
            }
            selectionAtGestureStart = nil
            synchronize(animated: !parent.reduceMotion)
        }
    }
}
