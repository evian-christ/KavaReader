import SwiftUI
import UIKit

private enum ZoomTapRegion {
    case left
    case center
    case right
}

struct ZoomableImageView: View {
    let pageNumber: Int
    let viewModel: ReaderViewModel
    let isActive: Bool
    let onTap: () -> Void
    let onPageChange: (Int) -> Void
    let onInteractionChange: (Bool) -> Void

    @State private var zoomScale: CGFloat = 1.0
    @State private var isInteracting = false
    @State private var displayedImage: UIImage?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var resetToken: Int = 0

    private let tapZoneWidth: CGFloat = 100
    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 4.0

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let image = displayedImage {
                ZoomableScrollView(
                    image: image,
                    zoomScale: $zoomScale,
                    isInteracting: $isInteracting,
                    maxZoom: maxZoom,
                    tapZoneWidth: tapZoneWidth,
                    resetTrigger: resetToken,
                    onSingleTap: handleSingleTap
                )
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

    private func handleSingleTap(region: ZoomTapRegion) {
        switch region {
        case .left:
            if zoomScale <= minZoom + 0.01 && pageNumber > 1 {
                onPageChange(pageNumber - 1)
            } else {
                onTap()
            }
        case .center:
            onTap()
        case .right:
            if zoomScale <= minZoom + 0.01 && pageNumber < viewModel.totalPages {
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
    let image: UIImage
    @Binding var zoomScale: CGFloat
    @Binding var isInteracting: Bool
    let maxZoom: CGFloat
    let tapZoneWidth: CGFloat
    let resetTrigger: Int
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
        var parent: ZoomableScrollView
        let imageView = UIImageView()
        var baseZoomScale: CGFloat = 1.0
        var maxZoomScale: CGFloat = 4.0
        var minZoomScale: CGFloat = 1.0
        private var previousBoundsSize: CGSize = .zero

        init(parent: ZoomableScrollView) {
            self.parent = parent
            super.init()
            imageView.contentMode = .scaleAspectFit
            imageView.isUserInteractionEnabled = false
            maxZoomScale = parent.maxZoom
        }

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

        private var lastResetTrigger: Int = -1

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
            if configureZoomScales(for: scrollView, resetZoom: shouldReset, newImage: isNewImage, resetTrigger: resetTrigger) {
                previousBoundsSize = scrollView.bounds.size
                lastResetTrigger = resetTrigger
            }
        }

        @discardableResult
        private func configureZoomScales(for scrollView: UIScrollView, resetZoom: Bool, newImage: Bool, resetTrigger: Int) -> Bool {
            guard let image = imageView.image, image.size.width > 0, image.size.height > 0 else { return false }
            let boundsSize = scrollView.bounds.size
            guard boundsSize.width > 0 && boundsSize.height > 0 else {
                DispatchQueue.main.async { [weak self, weak scrollView] in
                    guard
                        let self,
                        let scrollView = scrollView,
                        let _ = self.imageView.image
                    else { return }
                    _ = self.configureZoomScales(for: scrollView, resetZoom: resetZoom, newImage: newImage, resetTrigger: resetTrigger)
                }
                return false
            }

            let xScale = boundsSize.width / image.size.width
            let yScale = boundsSize.height / image.size.height
            let minScale = min(xScale, yScale)
            let maxScale = max(minScale * parent.maxZoom, minScale)
            let minZoomScale = max(0.1, minScale * 0.5)

            baseZoomScale = minScale
            maxZoomScale = maxScale
            self.minZoomScale = minZoomScale
            scrollView.minimumZoomScale = minZoomScale
            scrollView.maximumZoomScale = maxScale

            let minRelative = minZoomScale / max(minScale, 0.0001)
            let currentRelative = max(parent.zoomScale, minRelative)
            let targetScale: CGFloat
            if resetZoom {
                targetScale = minScale
            } else {
                targetScale = max(minZoomScale, min(maxScale, currentRelative * minScale))
            }

            if newImage {
                scrollView.contentSize = image.size
            }

            if abs(scrollView.zoomScale - targetScale) > 0.01 {
                scrollView.zoomScale = targetScale
            }

            parent.zoomScale = targetScale / minScale
            centerImage(in: scrollView)
            updateInteractionState(for: scrollView)
            if resetZoom {
                parent.isInteracting = false
                scrollView.setContentOffset(.zero, animated: false)
            }
            return true
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            parent.isInteracting = true
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard baseZoomScale > 0 else { return }
            parent.zoomScale = scrollView.zoomScale / baseZoomScale
            centerImage(in: scrollView)
            updateInteractionState(for: scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            guard baseZoomScale > 0 else { return }
            parent.zoomScale = scale / baseZoomScale
            if scale < baseZoomScale - 0.001 {
                scrollView.setZoomScale(baseZoomScale, animated: true)
                scrollView.setContentOffset(.zero, animated: true)
                parent.zoomScale = 1.0
            }
            updateInteractionState(for: scrollView)
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            if scrollView.zoomScale > baseZoomScale + 0.01 {
                parent.isInteracting = true
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

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            let location = gesture.location(in: imageView)
            let boundedCenter = CGPoint(
                x: max(0, min(location.x, imageView.bounds.width)),
                y: max(0, min(location.y, imageView.bounds.height))
            )
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

        private func centerImage(in scrollView: UIScrollView) {
            var frame = imageView.frame
            let boundsSize = scrollView.bounds.size

            if frame.size.width < boundsSize.width {
                frame.origin.x = (boundsSize.width - frame.size.width) / 2
            } else {
                frame.origin.x = 0
            }

            if frame.size.height < boundsSize.height {
                frame.origin.y = (boundsSize.height - frame.size.height) / 2
            } else {
                frame.origin.y = 0
            }

            imageView.frame = frame
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
            parent.isInteracting = isZoomed
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
