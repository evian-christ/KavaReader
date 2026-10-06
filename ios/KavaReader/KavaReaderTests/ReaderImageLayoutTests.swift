@testable import KavaReader
import SwiftUI
import Testing
import UIKit

@MainActor
struct ReaderImageLayoutTests {
    @Test func paperCurlCommitsCompletedTurnsAndHonorsPageOrder() throws {
        for pageIDs in [[1, 2, 3], [3, 2, 1]] {
            let state = PagerTestState()
            let selection = Binding<Int?>(get: { state.selection }, set: { state.selection = $0 })
            let pager = ReaderHorizontalPager(size: CGSize(width: 768, height: 1024),
                                              pageIDs: pageIDs, selection: selection, isZoomed: false) { page, _ in
                Text("\(page)")
            }
            let coordinator = pager.makeCoordinator()
            let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal)
            controller.dataSource = coordinator
            controller.delegate = coordinator
            coordinator.controller = controller
            coordinator.synchronize(animated: false)

            let current = try #require(controller.viewControllers?.first)
            let previous = try #require(coordinator.pageViewController(controller, viewControllerBefore: current))
            let next = try #require(coordinator.pageViewController(controller, viewControllerAfter: current))
            #expect(coordinator.pageViewController(controller, viewControllerBefore: previous) == nil)
            #expect(coordinator.pageViewController(controller, viewControllerAfter: next) == nil)

            coordinator.pageViewController(controller, willTransitionTo: [next])
            #expect(state.selection == 2)
            coordinator.pageViewController(controller, didFinishAnimating: true,
                                           previousViewControllers: [current], transitionCompleted: false)
            #expect(state.selection == 2)

            coordinator.pageViewController(controller, willTransitionTo: [next])
            controller.setViewControllers([next], direction: .forward, animated: false)
            coordinator.pageViewController(controller, didFinishAnimating: true,
                                           previousViewControllers: [current], transitionCompleted: true)
            #expect(state.selection == pageIDs[2])

            coordinator.parent = ReaderHorizontalPager(size: pager.size, pageIDs: pageIDs,
                                                       selection: selection, isZoomed: true) { page, _ in
                Text("\(page)")
            }
            coordinator.synchronize(animated: false)
            #expect(coordinator.pageViewController(controller, viewControllerBefore: next) == nil)
            #expect(controller.gestureRecognizers.allSatisfy { !$0.isEnabled })
            #expect(coordinator.pageViewController(controller, spineLocationFor: .landscapeLeft) == .min)
            #expect(!controller.isDoubleSided)
        }
    }

    @Test func doublePageCurlUsesIndividualFacesAroundTheCenterSpine() throws {
        for pageIDs in [[1, 3, 5], [5, 3, 1]] {
            let state = PagerTestState()
            state.selection = 3
            let selection = Binding<Int?>(get: { state.selection }, set: { state.selection = $0 })
            let pager = ReaderHorizontalPager(size: CGSize(width: 1024, height: 768),
                                              pageIDs: pageIDs, selection: selection, isZoomed: false,
                                              isDoublePage: true) { page, side in
                Text("\(page):\(side ?? -1)")
            }
            let coordinator = pager.makeCoordinator()
            let controller = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal,
                                                  options: [.spineLocation: pager.spineLocation.rawValue])
            controller.isDoubleSided = true
            controller.dataSource = coordinator
            controller.delegate = coordinator
            coordinator.controller = controller
            coordinator.synchronize(animated: false)

            let visible = try #require(controller.viewControllers)
            #expect(visible.count == 2)
            #expect((visible.first as? ReaderHorizontalPager<Text>.PageHost)?.key.side == 0)
            #expect((visible.last as? ReaderHorizontalPager<Text>.PageHost)?.key.side == 1)
            let left = try #require(visible.first)
            let right = try #require(visible.last)
            let backOfRight = try #require(coordinator.pageViewController(controller, viewControllerAfter: right))
            let nextRight = try #require(coordinator.pageViewController(controller, viewControllerAfter: backOfRight))
            #expect((backOfRight as? ReaderHorizontalPager<Text>.PageHost)?.key.side == 0)
            #expect((backOfRight as? ReaderHorizontalPager<Text>.PageHost)?.pageID == pageIDs[2])
            #expect((nextRight as? ReaderHorizontalPager<Text>.PageHost)?.key.side == 1)
            #expect((nextRight as? ReaderHorizontalPager<Text>.PageHost)?.pageID == pageIDs[2])
            #expect(coordinator.pageViewController(controller, viewControllerAfter: nextRight) == nil)

            let backOfLeft = try #require(coordinator.pageViewController(controller, viewControllerBefore: left))
            let previousLeft = try #require(coordinator.pageViewController(controller, viewControllerBefore: backOfLeft))
            #expect((backOfLeft as? ReaderHorizontalPager<Text>.PageHost)?.key.side == 1)
            #expect((backOfLeft as? ReaderHorizontalPager<Text>.PageHost)?.pageID == pageIDs[0])
            #expect(coordinator.pageViewController(controller, viewControllerBefore: previousLeft) == nil)

            coordinator.pageViewController(controller, willTransitionTo: [backOfRight, nextRight])
            coordinator.pageViewController(controller, didFinishAnimating: true,
                                           previousViewControllers: visible, transitionCompleted: false)
            #expect(state.selection == 3)
            #expect(controller.viewControllers?.first === left)
            #expect(controller.viewControllers?.last === right)

            coordinator.pageViewController(controller, willTransitionTo: [backOfRight, nextRight])
            controller.setViewControllers([backOfRight, nextRight], direction: .forward, animated: false)
            coordinator.pageViewController(controller, didFinishAnimating: true,
                                           previousViewControllers: visible, transitionCompleted: true)
            #expect(state.selection == pageIDs[2])

            state.selection = pageIDs[0]
            coordinator.synchronize(animated: false)
            #expect(controller.viewControllers?.count == 2)
            #expect((controller.viewControllers?.first as? ReaderHorizontalPager<Text>.PageHost)?.pageID == pageIDs[0])
            for orientation in [UIInterfaceOrientation.portrait, .landscapeLeft] {
                #expect(coordinator.pageViewController(controller, spineLocationFor: orientation) == .mid)
                #expect(controller.isDoubleSided)
            }
        }
    }

    @Test func horizontalPagerKeepsWindowPositionWhenReaderUIToggles() async throws {
        for size in [CGSize(width: 1024, height: 1366), CGSize(width: 1366, height: 1024)] {
            for pagesPerSpread in [1, 2] {
                let readers = (0 ..< 3 * pagesPerSpread).map { index in
                    makeReader(imageSize: CGSize(width: 800, height: 1200),
                               alignment: pagesPerSpread == 1 ? .center : (index.isMultiple(of: 2) ? .trailing : .leading))
                }
                let coordinators = readers.map { $0.makeCoordinator() }
                let viewports = zip(readers, coordinators).map { reader, coordinator in
                    reader.makeViewport(coordinator: coordinator)
                }
                let state = PagerTestState()
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                let controller = UIHostingController(rootView: PagerTestScene(state: state,
                                                                              viewports: viewports,
                                                                              pagesPerSpread: pagesPerSpread))
                window.rootViewController = controller
                window.isHidden = false
                defer {
                    window.isHidden = true
                    window.rootViewController = nil
                    withExtendedLifetime(coordinators) {}
                }

                // Simulate the ancestor's status-bar/home-indicator insets.
                // Comparing local image frames alone misses a shifted page host.
                controller.additionalSafeAreaInsets = UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)
                try await settleLayout(in: window)
                let activeViewports = Array(viewports[pagesPerSpread ..< 2 * pagesPerSpread])
                let images = try activeViewports.map { viewport in
                    try #require(viewport.window === window)
                    return try #require(viewport.scrollView.subviews.compactMap { $0 as? UIImageView }.first)
                }
                let normalFrames = images.map { $0.convert($0.bounds, to: window) }
                for frame in normalFrames {
                    #expect(frame.width > 0 && frame.height > 0)
                    #expect(window.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame))
                }

                for showsUI in [false, true, false, true] {
                    state.showsUI = showsUI
                    controller.additionalSafeAreaInsets.top = showsUI ? 24 : 0
                    try await settleLayout(in: window)
                    #expect(state.selection == 2)
                    for (image, expected) in zip(images, normalFrames) {
                        expectSameFrame(image.convert(image.bounds, to: window), expected)
                    }
                }

                // The parent pager must also stay put while the image is zoomed.
                activeViewports[0].scrollView.setZoomScale(2, animated: false)
                state.isZoomed = true
                try await settleLayout(in: window)
                let zoomedFrame = images[0].convert(images[0].bounds, to: window)
                state.showsUI = false
                controller.additionalSafeAreaInsets.top = 0
                try await settleLayout(in: window)
                #expect(activeViewports[0].scrollView.zoomScale == 2)
                expectSameFrame(images[0].convert(images[0].bounds, to: window), zoomedFrame)

                // A page selected while immersed must use the same vertical canvas.
                activeViewports[0].scrollView.setZoomScale(1, animated: false)
                state.isZoomed = false
                state.selection = 3
                // External page selections now animate before settling.
                try await Task.sleep(for: .milliseconds(700))
                try await settleLayout(in: window)
                try #require(viewports[2 * pagesPerSpread].window === window)
                let nextImage = try #require(viewports[2 * pagesPerSpread].scrollView.subviews.compactMap { $0 as? UIImageView }.first)
                expectSameFrame(nextImage.convert(nextImage.bounds, to: window), normalFrames[0])
            }
        }
    }

    @Test func imagePanOnlyCompetesWithPagerWhileZoomed() throws {
        let reader = makeReader(imageSize: CGSize(width: 800, height: 1200))
        let coordinator = reader.makeCoordinator()
        let viewport = reader.makeViewport(coordinator: coordinator)
        viewport.frame = CGRect(x: 0, y: 0, width: 1024, height: 1366)
        viewport.layoutIfNeeded()
        let scrollView = viewport.scrollView
        let pinch = try #require(scrollView.pinchGestureRecognizer)

        #expect(!scrollView.panGestureRecognizer.isEnabled)
        #expect(pinch.isEnabled)
        #expect(scrollView.gestureRecognizers?.contains(where: { $0 is UITapGestureRecognizer && $0.isEnabled }) == true)

        // Pinching/double-tapping can still enable panning of the enlarged image.
        scrollView.setZoomScale(2, animated: false)
        scrollView.layoutIfNeeded()
        #expect(scrollView.panGestureRecognizer.isEnabled)
        #expect(pinch.isEnabled)

        // Returning to 1x immediately gives horizontal swipes back to the pager.
        scrollView.setZoomScale(1, animated: false)
        scrollView.layoutIfNeeded()
        #expect(!scrollView.panGestureRecognizer.isEnabled)
        #expect(pinch.isEnabled)
        #expect(scrollView.contentOffset == .zero)
    }

    private func settleLayout(in window: UIWindow) async throws {
        // SwiftUI commits the bound selection and hosted layout asynchronously.
        for _ in 0 ..< 5 {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func expectSameFrame(_ actual: CGRect, _ expected: CGRect) {
        #expect(abs(actual.minX - expected.minX) < 0.5)
        #expect(abs(actual.minY - expected.minY) < 0.5)
        #expect(abs(actual.width - expected.width) < 0.5)
        #expect(abs(actual.height - expected.height) < 0.5)
    }

    @Test func fittedPagesStayInsideTheirViewportDuringContainerChanges() throws {
        // A page controller can temporarily move or resize its hosted page while
        // status-bar visibility changes. Cover both signs of the origin change,
        // rotation, a narrow spread slot, and resizing back to the original size.
        let frames = [
            CGRect(x: 0, y: 0, width: 768, height: 1024),
            CGRect(x: 0, y: 24, width: 768, height: 1024),
            CGRect(x: 0, y: -24, width: 768, height: 1024),
            CGRect(x: 0, y: 24, width: 768, height: 966),
            CGRect(x: 0, y: 0, width: 1024, height: 768),
            CGRect(x: 384, y: 24, width: 384, height: 966),
            CGRect(x: 0, y: 0, width: 768, height: 1024),
        ]
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 768, height: 1024))

        for imageSize in [CGSize(width: 200, height: 800), CGSize(width: 800, height: 200)] {
            for alignment in [ReaderPageAlignment.leading, .center, .trailing] {
                let reader = makeReader(imageSize: imageSize, alignment: alignment)
                let coordinator = reader.makeCoordinator()
                let viewport = reader.makeViewport(coordinator: coordinator)
                window.addSubview(viewport)
                defer { viewport.removeFromSuperview() }

                let imageView = try #require(viewport.scrollView.subviews.compactMap { $0 as? UIImageView }.first)
                for frame in frames {
                    viewport.frame = frame
                    viewport.setNeedsLayout()
                    viewport.layoutIfNeeded()

                    let imageFrame = imageView.convert(imageView.bounds, to: viewport)
                    #expect(viewport.bounds.insetBy(dx: -0.01, dy: -0.01).contains(imageFrame))
                    #expect(abs(imageFrame.midY - viewport.bounds.midY) < 0.01)
                    #expect(abs(imageFrame.width / imageFrame.height - imageSize.width / imageSize.height) < 0.01)
                    switch alignment {
                    case .leading:
                        #expect(abs(imageFrame.minX) < 0.01)
                    case .center:
                        #expect(abs(imageFrame.midX - viewport.bounds.midX) < 0.01)
                    case .trailing:
                        #expect(abs(imageFrame.maxX - viewport.bounds.maxX) < 0.01)
                    }
                    #expect(viewport.scrollView.zoomScale == 1)
                    #expect(viewport.scrollView.contentOffset == .zero)
                }
            }
        }
    }

    @Test func attachingToWindowDoesNotRepositionImageOrResetZoom() throws {
        let reader = makeReader(imageSize: CGSize(width: 800, height: 200))
        let coordinator = reader.makeCoordinator()
        let viewport = reader.makeViewport(coordinator: coordinator)
        viewport.frame = CGRect(x: 0, y: 24, width: 768, height: 966)
        viewport.layoutIfNeeded()
        let imageView = try #require(viewport.scrollView.subviews.compactMap { $0 as? UIImageView }.first)
        let initialFrame = imageView.frame

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 768, height: 1024))
        window.addSubview(viewport)
        viewport.setNeedsLayout()
        viewport.layoutIfNeeded()
        #expect(imageView.frame == initialFrame)

        viewport.scrollView.setZoomScale(2, animated: false)
        viewport.frame.origin.y = -24
        viewport.setNeedsLayout()
        viewport.layoutIfNeeded()
        #expect(viewport.scrollView.zoomScale == 2)

        viewport.scrollView.setZoomScale(1, animated: false)
        viewport.setNeedsLayout()
        viewport.layoutIfNeeded()
        #expect(imageView.frame == initialFrame)
    }

    @Test func verticalPagesKeepTheirFullWidthAndNaturalHeight() throws {
        let reader = makeReader(imageSize: CGSize(width: 200, height: 800), isHorizontal: false)
        let coordinator = reader.makeCoordinator()
        let viewport = reader.makeViewport(coordinator: coordinator)
        viewport.frame = CGRect(x: 0, y: 0, width: 768, height: 3072)
        viewport.layoutIfNeeded()
        let imageView = try #require(viewport.scrollView.subviews.compactMap { $0 as? UIImageView }.first)
        #expect(imageView.frame == viewport.bounds)
    }

    @Test func dynamicBackgroundCoversTopAndBottomAfterEveryResize() throws {
        let reader = makeReader(imageSize: CGSize(width: 800, height: 200))
        let coordinator = reader.makeCoordinator()
        let viewport = reader.makeViewport(coordinator: coordinator)

        for size in [CGSize(width: 768, height: 1024), CGSize(width: 768, height: 966),
                     CGSize(width: 1024, height: 768), CGSize(width: 384, height: 1024)] {
            viewport.frame = CGRect(origin: .zero, size: size)
            viewport.setNeedsLayout()
            viewport.layoutIfNeeded()

            // Render the actual layer tree: neither edge may expose a blank strip
            // or retain the opposite edge's color after the viewport changes size.
            let top = try pixel(in: viewport, at: CGPoint(x: size.width / 2, y: 0.5))
            let bottom = try pixel(in: viewport, at: CGPoint(x: size.width / 2, y: size.height - 0.5))
            #expect(top == [255, 0, 0, 255])
            #expect(bottom == [0, 0, 255, 255])
        }
    }

    private func pixel(in view: UIView, at point: CGPoint) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress,
                                                width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                                space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                                    CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x: 0.5 - point.x, y: 0.5 - point.y)
            view.layer.render(in: context)
        }
        return bytes
    }

    private func makeReader(imageSize: CGSize, alignment: ReaderPageAlignment = .center,
                            isHorizontal: Bool = true) -> ZoomableScrollView
    {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: imageSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: imageSize))
        }
        return ZoomableScrollView(image: image,
                                  edgeColors: PageEdgeColors(top: .red, bottom: .blue, left: .green, right: .yellow),
                                  maxZoom: 4,
                                  tapZoneWidth: 44,
                                  resetTrigger: 0,
                                  viewportFrame: .zero,
                                  isReaderUIVisible: true,
                                  isHorizontalReader: isHorizontal,
                                  horizontalImageAlignment: alignment,
                                  onSingleTap: { _, _ in },
                                  onInteractionChange: { _ in })
    }
}

@MainActor
private final class PagerTestState: ObservableObject {
    @Published var selection: Int? = 2
    @Published var showsUI = true
    @Published var isZoomed = false
}

private struct PagerTestScene: View {
    @ObservedObject var state: PagerTestState
    let viewports: [ReaderImageViewport]
    let pagesPerSpread: Int

    var body: some View {
        ZStack {
            ReaderCanvasHost {
                GeometryReader { geometry in
                    ReaderHorizontalPager(size: geometry.size, pageIDs: [1, 2, 3],
                                          selection: $state.selection, isZoomed: state.isZoomed,
                                          isDoublePage: pagesPerSpread == 2) { spread, side in
                        PagerViewportProbe(viewport: viewports[(spread - 1) * pagesPerSpread + (side ?? 0)])
                            .frame(width: geometry.size.width / CGFloat(pagesPerSpread), height: geometry.size.height)
                    }
                }
                .ignoresSafeArea(.container)
            }
            .ignoresSafeArea(.container)

            if state.showsUI {
                Color.clear.allowsHitTesting(false)
            }
        }
        .statusBarHidden(!state.showsUI)
    }
}

private struct PagerViewportProbe: UIViewRepresentable {
    let viewport: ReaderImageViewport

    func makeUIView(context: Context) -> ReaderImageViewport { viewport }
    func updateUIView(_ uiView: ReaderImageViewport, context: Context) {}
}
