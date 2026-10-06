import QuartzCore
import SwiftUI
import UIKit

enum ZoomTapRegion {
    case left
    case center
    case right
}

enum ReaderPageAlignment: Equatable {
    case leading
    case center
    case trailing
}

struct PageEdgeColors {
    let top: UIColor
    let bottom: UIColor
    let left: UIColor
    let right: UIColor

    static var fallback: PageEdgeColors {
        PageEdgeColors(top: UIColor(AppTheme.background),
                       bottom: UIColor(AppTheme.background),
                       left: UIColor(AppTheme.background),
                       right: UIColor(AppTheme.background))
    }

    init(top: UIColor, bottom: UIColor, left: UIColor, right: UIColor) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    init(image: UIImage) {
        let side = 64
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let thumbnail = renderer.image { context in
            UIColor(AppTheme.background).setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        guard let source = thumbnail.cgImage else {
            self = .fallback
            return
        }

        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let copied = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress,
                                          width: side,
                                          height: side,
                                          bitsPerComponent: 8,
                                          bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue |
                                              CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // Flip the UIKit image for Core Graphics drawing. Bitmap scanlines
            // are read from the opposite vertical edge below.
            context.translateBy(x: 0, y: CGFloat(side))
            context.scaleBy(x: 1, y: -1)
            context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard copied else {
            self = .fallback
            return
        }

        top = Self.dominantColor(in: pixels, side: side) { x, y in y >= side - 2 }
        bottom = Self.dominantColor(in: pixels, side: side) { x, y in y < 2 }
        left = Self.dominantColor(in: pixels, side: side) { x, y in x < 2 }
        right = Self.dominantColor(in: pixels, side: side) { x, y in x >= side - 2 }
    }

    private static func dominantColor(in pixels: [UInt8], side: Int,
                                      includes: (Int, Int) -> Bool) -> UIColor
    {
        var buckets: [Int: (count: Int, red: Int, green: Int, blue: Int)] = [:]
        for y in 0 ..< side {
            for x in 0 ..< side where includes(x, y) {
                let offset = (y * side + x) * 4
                let red = Int(pixels[offset])
                let green = Int(pixels[offset + 1])
                let blue = Int(pixels[offset + 2])
                let key = (red >> 4) << 8 | (green >> 4) << 4 | (blue >> 4)
                var bucket = buckets[key] ?? (count: 0, red: 0, green: 0, blue: 0)
                bucket.count += 1
                bucket.red += red
                bucket.green += green
                bucket.blue += blue
                buckets[key] = bucket
            }
        }
        guard let mostCommon = buckets.values.max(by: { $0.count < $1.count }) else {
            return UIColor(AppTheme.background)
        }
        return UIColor(red: CGFloat(mostCommon.red) / CGFloat(mostCommon.count * 255),
                       green: CGFloat(mostCommon.green) / CGFloat(mostCommon.count * 255),
                       blue: CGFloat(mostCommon.blue) / CGFloat(mostCommon.count * 255),
                       alpha: 1)
    }
}

private struct FrameModifier: ViewModifier {
    let scrollDirection: ScrollDirection
    let image: UIImage?
    let minimumViewportHeight: CGFloat
    let edgeColors: PageEdgeColors

    func body(content: Content) -> some View {
        if scrollDirection.isHorizontal {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            content
                .aspectRatio(image != nil ? image!.size : CGSize(width: 1, height: 1), contentMode: .fit)
                .frame(maxWidth: .infinity)
                // Loaded pages use their image height so vertical pages meet without gaps.
                .frame(minHeight: image == nil ? minimumViewportHeight : 0)
                .background {
                    LinearGradient(stops: [
                        .init(color: Color(edgeColors.top), location: 0),
                        .init(color: Color(edgeColors.top), location: 0.5),
                        .init(color: Color(edgeColors.bottom), location: 0.5),
                        .init(color: Color(edgeColors.bottom), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
        }
    }
}

struct ZoomableImageView: View {
    // MARK: Internal

    let pageNumber: Int
    let viewModel: ReaderViewModel
    let isActive: Bool
    let isReaderUIVisible: Bool
    let scrollDirection: ScrollDirection
    let extendPageEdges: Bool
    let tapEdgesToTurnPages: Bool
    let turnsPageFromLeftEdge: Bool
    let turnsPageFromRightEdge: Bool
    let horizontalImageAlignment: ReaderPageAlignment
    let minimumViewportHeight: CGFloat
    let onTap: () -> Void
    let onPageChange: (Int) -> Void
    let onFirstPageBack: () -> Void
    let onLastPageForward: () -> Void
    let onInteractionChange: (Bool) -> Void

    var body: some View {
        GeometryReader { geometry in
            let edgeTapWidth = min(tapZoneWidth, geometry.size.width * 0.25)

            ZStack {
                AppTheme.background
                    .ignoresSafeArea(.all)

                if let image = visibleImage {
                    ZoomableScrollView(image: image,
                                       edgeColors: effectiveEdgeColors,
                                       maxZoom: maxZoom,
                                       tapZoneWidth: edgeTapWidth,
                                       resetTrigger: resetToken,
                                       viewportFrame: imageViewportFrame,
                                       isReaderUIVisible: isReaderUIVisible,
                                       isHorizontalReader: scrollDirection.isHorizontal,
                                       horizontalImageAlignment: horizontalImageAlignment,
                                       onSingleTap: handleSingleTap,
                                       onInteractionChange: onInteractionChange)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            // Horizontal paging changes minX every frame. It is
                            // not an image-layout change and must not schedule
                            // alignment or SwiftUI state updates while swiping.
                            let frame = proxy.frame(in: .global)
                            return CGRect(x: 0, y: frame.minY,
                                          width: frame.width, height: frame.height)
                        } action: { frame in
                            imageViewportFrame = frame
                        }
                        .transition(.opacity)
                } else if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = loadError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 24))

                        Text(AppLocalization.text(error))
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // 로딩 중에도 탭 제스처를 받을 수 있도록 투명 오버레이 추가
                if visibleImage == nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { location in
                            let width = geometry.size.width
                            if location.x < edgeTapWidth {
                                handleSingleTap(region: .left)
                            } else if location.x > width - edgeTapWidth {
                                handleSingleTap(region: .right)
                            } else {
                                handleSingleTap(region: .center)
                            }
                        }
                }
            }
            .onChange(of: isActive) { _, newValue in
                guard newValue else { return }
                requestZoomReset()
            }
            .task(id: pageNumber) {
                await loadImage()
            }
        }
        .modifier(FrameModifier(scrollDirection: scrollDirection,
                                image: visibleImage,
                                minimumViewportHeight: minimumViewportHeight,
                                edgeColors: effectiveEdgeColors))
    }

    // MARK: Private

    @State private var displayedImage: UIImage?
    @State private var edgeColors = PageEdgeColors.fallback
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var resetToken: Int = 0
    @State private var imageViewportFrame: CGRect = .zero

    private var visibleImage: UIImage? {
        displayedImage ?? viewModel.getPreloadedImage(for: pageNumber)
    }

    private var effectiveEdgeColors: PageEdgeColors {
        extendPageEdges ? edgeColors : .fallback
    }

    private let tapZoneWidth: CGFloat = 100
    private let maxZoom: CGFloat = 4.0

    private func handleSingleTap(region: ZoomTapRegion, isZoomed: Bool = false) {
        if !tapEdgesToTurnPages {
            onTap()
            return
        }
        switch region {
        case .left:
            if isZoomed || !turnsPageFromLeftEdge {
                onTap()
            } else if scrollDirection.isRightToLeft {
                goForward()
            } else {
                goBack()
            }
        case .center:
            onTap()
        case .right:
            if isZoomed || !turnsPageFromRightEdge {
                onTap()
            } else if scrollDirection.isRightToLeft {
                goBack()
            } else {
                goForward()
            }
        }
    }

    private func goBack() {
        if pageNumber > 1 {
            onPageChange(pageNumber - 1)
        } else {
            onFirstPageBack()
        }
    }

    private func goForward() {
        if pageNumber < viewModel.totalPages {
            onPageChange(pageNumber + 1)
        } else {
            onLastPageForward()
        }
    }

    @MainActor
    private func loadImage() async {
        loadError = nil
        isLoading = true

        if let cached = viewModel.getPreloadedImage(for: pageNumber) {
            edgeColors = PageEdgeColors(image: cached)
            displayedImage = cached
            viewModel.didDisplayPage(pageNumber)
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
        edgeColors = PageEdgeColors(image: image)
        displayedImage = image
        viewModel.didDisplayPage(pageNumber)
        isLoading = false
        requestZoomReset()
    }

    @MainActor
    private func requestZoomReset() {
        resetToken &+= 1
    }
}

// Keep every background layer outside UIScrollView's animated content coordinates.
final class ReaderImageViewport: UIView {
    let scrollView = ReaderImageScrollView()
    private var imageSize: CGSize = .zero
    private var edgeColors = PageEdgeColors.fallback
    private let pageBackground = CAGradientLayer()
    private var renderedStartColor: UIColor?
    private var renderedEndColor: UIColor?
    private var renderedHasVerticalMargins: Bool?
    private let topMargin = CALayer()
    private let bottomMargin = CALayer()
    private let leftMargin = CALayer()
    private let rightMargin = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isOpaque = true
        pageBackground.locations = [0, 0.5, 0.5, 1]
        layer.addSublayer(pageBackground)
        for margin in [topMargin, bottomMargin, leftMargin, rightMargin] {
            layer.addSublayer(margin)
        }
        scrollView.backgroundColor = .clear
        scrollView.isOpaque = false
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateBackground(imageSize: CGSize, colors: PageEdgeColors) {
        self.imageSize = imageSize
        edgeColors = colors
        updateFixedBackground()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Resize the background, image and edge fills in one layout pass. A later
        // scroll-view pass can otherwise leave edge fills at the previous size.
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            updateFixedBackground()
            if scrollView.frame != bounds {
                scrollView.frame = bounds
            }
            scrollView.setNeedsLayout()
            scrollView.layoutIfNeeded()
            CATransaction.commit()
        }
    }

    private func updateFixedBackground() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let hasVerticalMargins = imageSize.width * bounds.height >= imageSize.height * bounds.width
        let startColor = hasVerticalMargins ? edgeColors.top : edgeColors.left
        let endColor = hasVerticalMargins ? edgeColors.bottom : edgeColors.right
        guard pageBackground.frame != bounds || renderedStartColor != startColor ||
            renderedEndColor != endColor || renderedHasVerticalMargins != hasVerticalMargins else { return }
        renderedStartColor = startColor
        renderedEndColor = endColor
        renderedHasVerticalMargins = hasVerticalMargins
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pageBackground.frame = bounds
        pageBackground.colors = [startColor.cgColor, startColor.cgColor, endColor.cgColor, endColor.cgColor]
        pageBackground.startPoint = hasVerticalMargins ? CGPoint(x: 0.5, y: 0) : CGPoint(x: 0, y: 0.5)
        pageBackground.endPoint = hasVerticalMargins ? CGPoint(x: 0.5, y: 1) : CGPoint(x: 1, y: 0.5)
        CATransaction.commit()
    }

    func updateMargins(around imageFrame: CGRect, colors: PageEdgeColors) {
        let visible = bounds
        let middleTop = max(visible.minY, imageFrame.minY)
        let middleBottom = min(visible.maxY, imageFrame.maxY)
        let middleHeight = max(0, middleBottom - middleTop)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        topMargin.backgroundColor = colors.top.cgColor
        bottomMargin.backgroundColor = colors.bottom.cgColor
        leftMargin.backgroundColor = colors.left.cgColor
        rightMargin.backgroundColor = colors.right.cgColor
        topMargin.frame = CGRect(x: visible.minX, y: visible.minY,
                                 width: visible.width, height: max(0, imageFrame.minY - visible.minY))
        bottomMargin.frame = CGRect(x: visible.minX, y: max(visible.minY, imageFrame.maxY),
                                    width: visible.width, height: max(0, visible.maxY - imageFrame.maxY))
        leftMargin.frame = CGRect(x: visible.minX, y: middleTop,
                                  width: max(0, imageFrame.minX - visible.minX), height: middleHeight)
        rightMargin.frame = CGRect(x: max(visible.minX, imageFrame.maxX), y: middleTop,
                                   width: max(0, visible.maxX - imageFrame.maxX), height: middleHeight)
        CATransaction.commit()
    }
}

// UIKit owns the zoom scale. At 1x, horizontal pages fit inside both viewport dimensions.
final class ReaderImageScrollView: UIScrollView {
    var onLayout: ((ReaderImageScrollView) -> Void)?

    override func layoutSubviews() {
        if zoomScale == 1 && !isZooming && !isZoomBouncing {
            // Status-bar transitions can lend their animation to image layout
            // while the margin layers already update immediately. Keep them in
            // the same unanimated pass, while preserving animated zoom gestures.
            UIView.performWithoutAnimation {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layoutImageSubviews()
                CATransaction.commit()
            }
        } else {
            layoutImageSubviews()
        }
    }

    private func layoutImageSubviews() {
        super.layoutSubviews()
        onLayout?(self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // Recheck the final viewport size after attachment.
        setNeedsLayout()
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer && zoomScale <= 1.01 {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

struct ZoomableScrollView: UIViewRepresentable {
    let image: UIImage
    let edgeColors: PageEdgeColors
    let maxZoom: CGFloat
    let tapZoneWidth: CGFloat
    let resetTrigger: Int
    // Track size and global Y for status-bar changes, excluding horizontal
    // translation caused by paging (the reported frame's X is always zero).
    let viewportFrame: CGRect
    let isReaderUIVisible: Bool
    let isHorizontalReader: Bool
    let horizontalImageAlignment: ReaderPageAlignment
    let onSingleTap: (ZoomTapRegion, Bool) -> Void
    let onInteractionChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ReaderImageViewport {
        makeViewport(coordinator: context.coordinator)
    }

    func makeViewport(coordinator: Coordinator) -> ReaderImageViewport {
        let viewport = ReaderImageViewport()
        viewport.updateBackground(imageSize: image.size, colors: edgeColors)
        let scrollView = viewport.scrollView
        scrollView.delegate = coordinator
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = maxZoom
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delaysContentTouches = false
        coordinator.setup(in: scrollView)
        scrollView.onLayout = { [weak coordinator] view in
            coordinator?.layout(in: view)
        }
        coordinator.update(image: image, in: scrollView)
        return viewport
    }

    func updateUIView(_ viewport: ReaderImageViewport, context: Context) {
        viewport.updateBackground(imageSize: image.size, colors: edgeColors)
        let scrollView = viewport.scrollView
        let visibilityChanged = context.coordinator.parent.isReaderUIVisible != isReaderUIVisible
        let needsAlignment = context.coordinator.parent.viewportFrame != viewportFrame ||
            visibilityChanged || context.coordinator.parent.horizontalImageAlignment != horizontalImageAlignment
        if visibilityChanged {
            context.coordinator.captureZoomAnchor(in: scrollView)
        }
        context.coordinator.parent = self
        context.coordinator.update(image: image, in: scrollView)
        if needsAlignment {
            // Geometry is reported after the ancestor layout. Recenter against that
            // completed layout, without resetting zoom or the reader's page state.
            context.coordinator.scheduleAlignment(in: scrollView)
        }
    }

    static func dismantleUIView(_ viewport: ReaderImageViewport, coordinator: Coordinator) {
        let scrollView = viewport.scrollView
        scrollView.onLayout = nil
        scrollView.delegate = nil
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        private struct ZoomAnchor {
            let imagePoint: CGPoint
            let windowPoint: CGPoint
            let windowBounds: CGRect
        }

        var parent: ZoomableScrollView
        private let imageView = UIImageView()
        private var fittedSize: CGSize = .zero
        private var fittedViewportSize: CGSize = .zero
        private var fittedForHorizontalReader = false
        private var lastResetTrigger: Int?
        private var needsReset = true
        private var isLayingOut = false
        private var lastInteractionState = false
        private var isAlignmentScheduled = false
        private var zoomAnchor: ZoomAnchor?
        private weak var edgeTap: UITapGestureRecognizer?

        init(parent: ZoomableScrollView) {
            self.parent = parent
            super.init()
            imageView.contentMode = .scaleAspectFit
            imageView.isUserInteractionEnabled = false
        }

        func setup(in scrollView: UIScrollView) {
            scrollView.addSubview(imageView)

            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
            doubleTap.numberOfTapsRequired = 2
            configure(doubleTap, in: scrollView)

            let centerTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
            centerTap.require(toFail: doubleTap)
            configure(centerTap, in: scrollView)

            // Page-turn taps do not wait for the center area's double-tap zoom recognizer.
            let edgeTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
            self.edgeTap = edgeTap
            configure(edgeTap, in: scrollView)
        }

        private func configure(_ recognizer: UITapGestureRecognizer, in scrollView: UIScrollView) {
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            scrollView.addGestureRecognizer(recognizer)
        }

        func update(image: UIImage, in scrollView: UIScrollView) {
            if imageView.image !== image {
                imageView.image = image
                needsReset = true
            }
            if lastResetTrigger != parent.resetTrigger {
                needsReset = true
                lastResetTrigger = parent.resetTrigger
            }
            // Safe-area/UI updates only request layout; they never reapply a zoom value.
            scrollView.setNeedsLayout()
        }

        func scheduleAlignment(in scrollView: UIScrollView) {
            guard !isAlignmentScheduled else { return }
            isAlignmentScheduled = true
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self else { return }
                self.isAlignmentScheduled = false
                guard let scrollView, scrollView.window != nil else { return }
                scrollView.setNeedsLayout()
                scrollView.layoutIfNeeded()
            }
        }

        func captureZoomAnchor(in scrollView: UIScrollView) {
            guard zoomAnchor == nil, scrollView.zoomScale > 1.01,
                  let window = scrollView.window else { return }
            let point = CGPoint(x: window.bounds.midX, y: window.bounds.midY)
            zoomAnchor = ZoomAnchor(imagePoint: imageView.convert(point, from: window),
                                    windowPoint: point,
                                    windowBounds: window.bounds)
        }

        private func restoreZoomAnchor(in scrollView: UIScrollView) {
            guard let anchor = zoomAnchor, let window = scrollView.window else { return }
            guard scrollView.zoomScale > 1.01, window.bounds == anchor.windowBounds else {
                zoomAnchor = nil
                return
            }
            let currentPoint = imageView.convert(anchor.imagePoint, to: scrollView)
            let targetPoint = scrollView.convert(anchor.windowPoint, from: window)
            let offset = CGPoint(x: scrollView.contentOffset.x + currentPoint.x - targetPoint.x,
                                 y: scrollView.contentOffset.y + currentPoint.y - targetPoint.y)

            // At an image edge the correction may lie outside the old scroll range.
            // Permit that offset so UIKit cannot clamp it back on the next layout.
            let inset = UIEdgeInsets(top: max(0, -offset.y),
                                     left: max(0, -offset.x),
                                     bottom: max(0, offset.y + scrollView.bounds.height - scrollView.contentSize.height),
                                     right: max(0, offset.x + scrollView.bounds.width - scrollView.contentSize.width))
            if scrollView.contentInset != inset { scrollView.contentInset = inset }
            if abs(scrollView.contentOffset.x - offset.x) > 0.5 || abs(scrollView.contentOffset.y - offset.y) > 0.5 {
                scrollView.setContentOffset(offset, animated: false)
            }
        }

        func layout(in scrollView: UIScrollView) {
            guard !isLayingOut,
                  let image = imageView.image,
                  image.size.width > 0, image.size.height > 0,
                  scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return }
            isLayingOut = true
            defer { isLayingOut = false }

            let viewportSize = scrollView.bounds.size
            let widthChanged = abs(fittedViewportSize.width - viewportSize.width) > 0.5
            let heightChanged = abs(fittedViewportSize.height - viewportSize.height) > 0.5
            let needsHeightRefit = parent.isHorizontalReader && heightChanged && scrollView.zoomScale <= 1.01
            if needsReset || widthChanged || needsHeightRefit || fittedForHorizontalReader != parent.isHorizontalReader {
                zoomAnchor = nil
                scrollView.contentInset = .zero
                // Reset UIKit's transform before changing the image's unscaled bounds.
                scrollView.setZoomScale(1, animated: false)
                imageView.transform = .identity
                let widthScale = viewportSize.width / image.size.width
                let fitScale = parent.isHorizontalReader
                    ? min(widthScale, viewportSize.height / image.size.height)
                    : widthScale
                fittedSize = CGSize(width: image.size.width * fitScale,
                                    height: image.size.height * fitScale)
                fittedViewportSize = viewportSize
                fittedForHorizontalReader = parent.isHorizontalReader
                imageView.bounds = CGRect(origin: .zero, size: fittedSize)
                imageView.center = CGPoint(x: fittedSize.width / 2, y: fittedSize.height / 2)
                scrollView.contentSize = fittedSize
                scrollView.setContentOffset(.zero, animated: false)
                needsReset = false
            }
            centerImage(in: scrollView)
            updateMargins(in: scrollView)
            reportInteraction(in: scrollView)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            zoomAnchor = nil
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            zoomAnchor = nil
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard !isLayingOut else { return }
            centerImage(in: scrollView)
            updateMargins(in: scrollView)
            reportInteraction(in: scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            guard !isLayingOut else { return }
            centerImage(in: scrollView)
            updateMargins(in: scrollView)
            reportInteraction(in: scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateMargins(in: scrollView)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let scrollView = gestureRecognizer.view as? UIScrollView else { return false }
            let x = touch.location(in: scrollView).x - scrollView.bounds.minX
            let isEdge = x < parent.tapZoneWidth || x > scrollView.bounds.width - parent.tapZoneWidth
            return gestureRecognizer === edgeTap ? isEdge : !isEdge
        }

        @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            let x = gesture.location(in: scrollView).x - scrollView.bounds.minX
            let region: ZoomTapRegion
            if x < parent.tapZoneWidth {
                region = .left
            } else if x > scrollView.bounds.width - parent.tapZoneWidth {
                region = .right
            } else {
                region = .center
            }
            // Capture before SwiftUI moves any ancestors for the status-bar change.
            captureZoomAnchor(in: scrollView)
            parent.onSingleTap(region, scrollView.zoomScale > 1.01)
        }

        @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            zoomAnchor = nil
            if scrollView.zoomScale > 1.01 {
                scrollView.setZoomScale(1, animated: true)
            } else {
                let scale = min(parent.maxZoom, 2)
                let location = gesture.location(in: imageView)
                let size = CGSize(width: scrollView.bounds.width / scale,
                                  height: scrollView.bounds.height / scale)
                let rect = CGRect(x: location.x - size.width / 2, y: location.y - size.height / 2,
                                  width: size.width, height: size.height)
                scrollView.zoom(to: rect, animated: true)
            }
        }

        private func centerImage(in scrollView: UIScrollView) {
            guard fittedSize.width > 0 else { return }
            let displayedSize = CGSize(width: fittedSize.width * scrollView.zoomScale,
                                       height: fittedSize.height * scrollView.zoomScale)
            if abs(scrollView.contentSize.width - displayedSize.width) > 0.5 ||
               abs(scrollView.contentSize.height - displayedSize.height) > 0.5 {
                scrollView.contentSize = displayedSize
            }
            if scrollView.zoomScale == 1 {
                zoomAnchor = nil
                if scrollView.contentInset != .zero { scrollView.contentInset = .zero }
                if scrollView.contentOffset != .zero {
                    scrollView.setContentOffset(.zero, animated: false)
                }
            }
            let boundsSize = scrollView.bounds.size
            var center = CGPoint(x: max(displayedSize.width, boundsSize.width) / 2,
                                 y: max(displayedSize.height, boundsSize.height) / 2)
            if parent.isHorizontalReader, scrollView.zoomScale <= 1.01 {
                // Keep paired pages touching at the center; any spare width stays outside the spread.
                switch parent.horizontalImageAlignment {
                case .leading:
                    center.x = displayedSize.width / 2
                case .center:
                    break
                case .trailing:
                    center.x = boundsSize.width - displayedSize.width / 2
                }
            }
            // Fit, center and edge fills all use this viewport's coordinates.
            // Centering in window coordinates can put part of a fitted page outside
            // the clipping bounds while a page controller updates its safe area.
            if abs(imageView.center.x - center.x) > 0.5 || abs(imageView.center.y - center.y) > 0.5 {
                imageView.center = center
            }
            restoreZoomAnchor(in: scrollView)
        }

        private func reportInteraction(in scrollView: UIScrollView) {
            let isZoomed = scrollView.zoomScale > 1.01
            // At 1x only the outer pager should recognize a pan. Merely rejecting
            // the inner pan in shouldBegin still participates in nested-scroll
            // gesture arbitration. Pinch and double-tap zoom remain enabled.
            if scrollView.panGestureRecognizer.isEnabled != isZoomed {
                scrollView.panGestureRecognizer.isEnabled = isZoomed
            }
            guard isZoomed != lastInteractionState else { return }
            lastInteractionState = isZoomed
            parent.onInteractionChange(isZoomed)
        }

        private func updateMargins(in scrollView: UIScrollView) {
            guard let viewport = scrollView.superview as? ReaderImageViewport else { return }
            let imageFrame = scrollView.convert(imageView.frame, to: viewport)
            viewport.updateMargins(around: imageFrame, colors: parent.edgeColors)
        }
    }
}
