import SwiftUI
import UIKit

private enum ZoomTapRegion {
    case left
    case center
    case right
}

struct ZoomableImageView: View {
    // MARK: Internal

    let pageNumber: Int
    let viewModel: ReaderViewModel
    let isActive: Bool
    let pageFitMode: PageFitMode
    let onTap: () -> Void
    let onPageChange: (Int) -> Void
    let onInteractionChange: (Bool) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea(.all)

                if let image = displayedImage {
                    ZoomableScrollView(pageNumber: pageNumber,
                                       image: image,
                                       zoomScale: $zoomScale,
                                       isInteracting: $isInteracting,
                                       maxZoom: maxZoom,
                                       tapZoneWidth: tapZoneWidth,
                                       resetTrigger: resetToken,
                                       pageFitMode: pageFitMode,
                                       onSingleTap: handleSingleTap)
                        .transition(.opacity)
                } else if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else if let error = loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 24))

                        Text(error)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)

                        Button(action: {
                            Task {
                                await loadImage()
                            }
                        }) {
                            Text("다시 시도")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(8)
                        }
                    }
                    .padding(24)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                }

                // 로딩 중에도 탭 제스처를 받을 수 있도록 투명 오버레이 추가
                if displayedImage == nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let width = geometry.size.width
                            if location.x < tapZoneWidth {
                                handleSingleTap(region: .left)
                            } else if location.x > width - tapZoneWidth {
                                handleSingleTap(region: .right)
                            } else {
                                handleSingleTap(region: .center)
                            }
                        }
                }
            }
            .onChange(of: isInteracting) { _, newValue in
                onInteractionChange(newValue)
            }
            .onChange(of: isActive) { _, newValue in
                guard newValue else { return }
                requestZoomReset()
            }
            .task(id: pageNumber) {
                await loadImage()
            }
        }
    }

    // MARK: Private

    @State private var zoomScale: CGFloat = 1.0
    @State private var isInteracting = false
    @State private var displayedImage: UIImage?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var resetToken: Int = 0

    private let tapZoneWidth: CGFloat = 100
    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 4.0

    private func handleSingleTap(region: ZoomTapRegion) {
        switch region {
        case .left:
            if zoomScale <= minZoom + 0.01, pageNumber > 1 {
                onPageChange(pageNumber - 1)
            } else {
                onTap()
            }
        case .center:
            onTap()
        case .right:
            if zoomScale <= minZoom + 0.01, pageNumber < viewModel.totalPages {
                onPageChange(pageNumber + 1)
            } else {
                onTap()
            }
        }
    }

    @MainActor
    private func loadImage() async {
        loadError = nil
        isLoading = true
        isInteracting = false
        zoomScale = 1.0

        if let cached = viewModel.getPreloadedImage(for: pageNumber) {
            displayedImage = cached
            isLoading = false
            requestZoomReset()
            return
        }

        guard let image = await viewModel.loadImageForReader(pageNumber: pageNumber) else {
            if Task.isCancelled {
                isLoading = false
                return
            }
            isLoading = false
            loadError = viewModel.errorMessage ?? "이미지를 불러오지 못했어요."
            return
        }

        if Task.isCancelled {
            isLoading = false
            return
        }
        displayedImage = image
        isLoading = false
        requestZoomReset()
    }

    @MainActor
    private func requestZoomReset() {
        zoomScale = 1.0
        isInteracting = false
        resetToken &+= 1
    }
}

private struct ZoomableScrollView: UIViewRepresentable {
    let pageNumber: Int
    let image: UIImage
    @Binding var zoomScale: CGFloat
    @Binding var isInteracting: Bool
    let maxZoom: CGFloat
    let tapZoneWidth: CGFloat
    let resetTrigger: Int
    let pageFitMode: PageFitMode
    let onSingleTap: (ZoomTapRegion) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.backgroundColor = .black
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.bounces = true
        scrollView.maximumZoomScale = 1.0
        scrollView.minimumZoomScale = 1.0
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.contentInsetAdjustmentBehavior = .never

        context.coordinator.setup(in: scrollView)
        context.coordinator.update(image: image, in: scrollView, resetZoom: true, resetTrigger: resetTrigger)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(image: image, in: scrollView, resetZoom: false, resetTrigger: resetTrigger)

        let baseScale = context.coordinator.baseZoomScale
        let minScale = context.coordinator.minZoomScale
        let targetScale = max(minScale, min(context.coordinator.maxZoomScale, baseScale * zoomScale))
        if abs(scrollView.zoomScale - targetScale) > 0.01 {
            scrollView.setZoomScale(targetScale, animated: false)
        }

        scrollView.isScrollEnabled = zoomScale > 1.01
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        // MARK: Lifecycle

        init(parent: ZoomableScrollView) {
            self.parent = parent
            super.init()
            imageView.contentMode = .scaleAspectFit
            imageView.isUserInteractionEnabled = false
            maxZoomScale = parent.maxZoom
        }

        // MARK: Internal

        var parent: ZoomableScrollView
        let imageView = UIImageView()
        var baseZoomScale: CGFloat = 1.0
        var maxZoomScale: CGFloat = 4.0
        var minZoomScale: CGFloat = 1.0

        func setup(in scrollView: UIScrollView) {
            scrollView.addSubview(imageView)

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            doubleTap.delegate = self
            scrollView.addGestureRecognizer(doubleTap)

            let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
            singleTap.delegate = self
            singleTap.require(toFail: doubleTap)
            scrollView.addGestureRecognizer(singleTap)
        }

        func update(image: UIImage, in scrollView: UIScrollView, resetZoom: Bool, resetTrigger: Int) {
            let isNewImage: Bool
            if imageView.image === image {
                isNewImage = false
            } else {
                imageView.image = image
                imageView.frame = CGRect(origin: .zero, size: image.size)
                isNewImage = true
            }

            let boundsChanged = scrollView.bounds.size != previousBoundsSize
            let shouldReset = resetZoom || isNewImage || boundsChanged || resetTrigger != lastResetTrigger
            if configureZoomScales(for: scrollView, resetZoom: shouldReset, newImage: isNewImage,
                                   resetTrigger: resetTrigger)
            {
                previousBoundsSize = scrollView.bounds.size
                lastResetTrigger = resetTrigger
            }
        }

        func viewForZooming(in _: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewWillBeginZooming(_: UIScrollView, with _: UIView?) {
            parent.isInteracting = true
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard baseZoomScale > 0 else { return }
            let normalizedScale = scrollView.zoomScale / baseZoomScale
            if abs(parent.zoomScale - normalizedScale) > 0.0001 {
                parent.zoomScale = normalizedScale
            }
            centerImage(in: scrollView, resetPosition: false)
            updateInteractionState(for: scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with _: UIView?, atScale scale: CGFloat) {
            guard baseZoomScale > 0 else { return }
            let normalizedScale = scale / baseZoomScale
            if abs(parent.zoomScale - normalizedScale) > 0.0001 {
                parent.zoomScale = normalizedScale
            }
            if scale < baseZoomScale - 0.001 {
                scrollView.setZoomScale(baseZoomScale, animated: true)
                parent.zoomScale = 1.0
            }
            centerImage(in: scrollView, resetPosition: true)
            updateInteractionState(for: scrollView)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            if scrollView.zoomScale > baseZoomScale + 0.01 {
                if !parent.isInteracting {
                    parent.isInteracting = true
                }
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                updateInteractionState(for: scrollView)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            updateInteractionState(for: scrollView)
        }

        func gestureRecognizer(_: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool
        {
            true
        }

        // MARK: Private

        private var previousBoundsSize: CGSize = .zero

        private var lastResetTrigger: Int = -1

        @discardableResult
        private func configureZoomScales(for scrollView: UIScrollView, resetZoom: Bool, newImage: Bool,
                                         resetTrigger: Int) -> Bool
        {
            guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else { return false }
            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 0 && boundsSize.height > 0 else {
                DispatchQueue.main.async { [weak self, weak scrollView] in
                    guard
                        let self,
                        let scrollView = scrollView,
                        let _ = self.imageView.image
                    else { return }
                    _ = self.configureZoomScales(for: scrollView, resetZoom: resetZoom, newImage: newImage,
                                                 resetTrigger: resetTrigger)
                }
                return false
            }

            let xScale = boundsSize.width / image.size.width
            let yScale = boundsSize.height / image.size.height

            // 현재는 너비에 맞춤만 사용되므로 xScale을 기본 배율로 사용
            let baseScale = xScale

            let maxScale = max(baseScale * parent.maxZoom, baseScale)
            let minZoomScale = max(0.1, min(baseScale, min(xScale, yScale)) * 0.5)

            print("📐 [Page \(parent.pageNumber)] Zoom Config:")
            print("  - Image size: \(image.size.width) x \(image.size.height)")
            print("  - Bounds size: \(boundsSize.width) x \(boundsSize.height)")
            print("  - xScale: \(xScale), yScale: \(yScale)")
            print("  - baseScale: \(baseScale)")
            print("  - resetZoom: \(resetZoom), newImage: \(newImage)")
            print("  - current scrollView.zoomScale: \(scrollView.zoomScale)")

            baseZoomScale = baseScale
            maxZoomScale = maxScale
            self.minZoomScale = minZoomScale
            scrollView.minimumZoomScale = minZoomScale
            scrollView.maximumZoomScale = maxScale

            let minRelative = minZoomScale / max(baseScale, 0.0001)
            let currentRelative = max(parent.zoomScale, minRelative)
            let targetScale: CGFloat
            if resetZoom {
                targetScale = baseScale
            } else {
                targetScale = max(minZoomScale, min(maxScale, currentRelative * baseScale))
            }

            print("  - targetScale: \(targetScale)")
            print("  - minZoomScale: \(minZoomScale), maxScale: \(maxScale)")

            // zoomScale을 먼저 설정한 후 contentSize 설정
            if abs(scrollView.zoomScale - targetScale) > 0.01 || newImage {
                print("  ⚠️ Setting zoomScale from \(scrollView.zoomScale) to \(targetScale)")
                scrollView.zoomScale = targetScale
            } else {
                print("  ✓ ZoomScale already correct")
            }

            if newImage {
                scrollView.contentSize = image.size
            }

            let normalizedScale = targetScale / baseScale
            if abs(parent.zoomScale - normalizedScale) > 0.0001 {
                parent.zoomScale = normalizedScale
            }

            let boundsChanged = scrollView.bounds.size != previousBoundsSize
            let shouldResetPosition = resetZoom || newImage || boundsChanged || resetTrigger != lastResetTrigger

            centerImage(in: scrollView, resetPosition: shouldResetPosition)
            updateInteractionState(for: scrollView)

            if resetZoom {
                if parent.isInteracting {
                    parent.isInteracting = false
                }
            }
            return true
        }

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            let location = gesture.location(in: imageView)
            let boundedCenter = CGPoint(x: max(0, min(location.x, imageView.bounds.width)),
                                        y: max(0, min(location.y, imageView.bounds.height)))
            let currentRelative = scrollView.zoomScale / max(baseZoomScale, 0.0001)

            if currentRelative > 1.01 {
                scrollView.setZoomScale(baseZoomScale, animated: true)
            } else {
                let targetRelative = min(parent.maxZoom, currentRelative * 2)
                let targetScale = baseZoomScale * targetRelative
                let zoomRect = zoomRect(for: scrollView, scale: targetScale, center: boundedCenter)
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }

        @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            let location = gesture.location(in: scrollView)
            let width = scrollView.bounds.width

            let region: ZoomTapRegion
            if location.x < parent.tapZoneWidth {
                region = .left
            } else if location.x > width - parent.tapZoneWidth {
                region = .right
            } else {
                region = .center
            }

            parent.onSingleTap(region)
        }

        private func centerImage(in scrollView: UIScrollView, resetPosition: Bool) {
            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 0, boundsSize.height > 0 else { return }

            let zoomScale = scrollView.zoomScale
            guard let image = imageView.image else { return }
            let imageSize = image.size

            // imageView.frame의 크기가 잘못되어 있으면 수정
            let expectedFrameSize = CGSize(width: imageSize.width * zoomScale,
                                          height: imageSize.height * zoomScale)
            if abs(imageView.frame.width - expectedFrameSize.width) > 1.0 ||
               abs(imageView.frame.height - expectedFrameSize.height) > 1.0 {
                print("⚠️ [Page \(parent.pageNumber)] Fixing imageView.frame from \(imageView.frame.size) to \(expectedFrameSize)")
                imageView.frame.size = expectedFrameSize
            }

            let displayWidth = imageSize.width * zoomScale
            let displayHeight = imageSize.height * zoomScale

            print("🖼️ [Page \(parent.pageNumber)] centerImage:")
            print("  - scrollView.zoomScale: \(zoomScale)")
            print("  - imageView.frame: \(imageView.frame)")
            print("  - imageView.bounds: \(imageView.bounds)")
            print("  - contentSize: \(scrollView.contentSize)")
            print("  - displaySize: \(displayWidth) x \(displayHeight)")

            let horizontalPadding = max(0, (boundsSize.width - displayWidth) / 2)
            let verticalPadding = max(0, (boundsSize.height - displayHeight) / 2)

            let centerHorizontally = false
            let centerVertically = true

            let insetLeft = centerHorizontally ? horizontalPadding : 0
            let insetRight = centerHorizontally ? horizontalPadding : 0
            let insetTop = centerVertically ? verticalPadding : 0
            let insetBottom = centerVertically ? verticalPadding : 0

            let targetInset = UIEdgeInsets(top: insetTop,
                                           left: insetLeft,
                                           bottom: insetBottom,
                                           right: insetRight)

            if scrollView.contentInset != targetInset {
                scrollView.contentInset = targetInset
            }

            if resetPosition && !parent.isInteracting {
                let targetOffset = CGPoint(x: -insetLeft, y: -insetTop)
                let currentOffset = scrollView.contentOffset
                if abs(currentOffset.x - targetOffset.x) > 0.5 || abs(currentOffset.y - targetOffset.y) > 0.5 {
                    scrollView.setContentOffset(targetOffset, animated: false)
                }
            }
        }

        private func zoomRect(for scrollView: UIScrollView, scale: CGFloat, center: CGPoint) -> CGRect {
            var zoomRect = CGRect.zero
            zoomRect.size.height = scrollView.bounds.height / scale
            zoomRect.size.width = scrollView.bounds.width / scale
            zoomRect.origin.x = center.x - (zoomRect.size.width / 2.0)
            zoomRect.origin.y = center.y - (zoomRect.size.height / 2.0)
            return zoomRect
        }

        private func updateInteractionState(for scrollView: UIScrollView) {
            guard baseZoomScale > 0 else { return }
            let isZoomed = scrollView.zoomScale > baseZoomScale + 0.01
            if parent.isInteracting != isZoomed {
                parent.isInteracting = isZoomed
            }
        }
    }
}
