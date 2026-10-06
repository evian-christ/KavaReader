import QuartzCore
import SwiftUI
import UIKit

struct PageStripView: View {
    @Binding var currentPage: Int

    let totalPages: Int
    let isRightToLeft: Bool
    let expandedControlLeadingInset: CGFloat
    let expandedControlTrailingInset: CGFloat
    let onPageChange: (Int) -> Void
    let loadPreview: ((Int) async -> UIImage?)?

    @Environment(\.displayScale) private var displayScale
    @State private var isExpanded = false
    @State private var isClosing = false
    @State private var showsPageBorders = false
    @State private var expansionID = UUID()
    @State private var carouselPosition: CGFloat
    @State private var dragStartPosition: CGFloat?
    @State private var pageDragAxis: PageDragAxis?
    @State private var coastTask: Task<Void, Never>?
    @State private var interruptedCoastInGesture = false
    @State private var isScrubbing = false
    @State private var availableControlWidth: CGFloat = 0
    @State private var buttonStyleWidth: CGFloat = 0
    @State private var previewImages: [Int: UIImage] = [:]

    private let maximumCardHeight: CGFloat = 240
    private let cardSpacing: CGFloat = 4
    private let cardCornerRadius: CGFloat = 3
    private let visibleEdgeCardFraction: CGFloat = 0.35
    private let previewPreloadRadius = 5 // Five visible pages plus three extra pages on each side.
    private let progressBarWidth: CGFloat = 90
    private let pageControlHeight: CGFloat = 44

    private enum PageDragAxis {
        case horizontal
        case vertical
    }

    private var displayedPage: Int {
        isExpanded ? clampedPage(Int(carouselPosition.rounded())) : currentPage
    }

    private var isPhone: Bool { UIDevice.current.userInterfaceIdiom == .phone }

    private var directionSign: CGFloat { isRightToLeft ? -1 : 1 }

    init(currentPage: Binding<Int>, totalPages: Int, isRightToLeft: Bool = false,
         expandedControlLeadingInset: CGFloat = 0, expandedControlTrailingInset: CGFloat = 0,
         loadPreview: ((Int) async -> UIImage?)? = nil,
         onPageChange: @escaping (Int) -> Void)
    {
        self._currentPage = currentPage
        self.totalPages = totalPages
        self.isRightToLeft = isRightToLeft
        self.expandedControlLeadingInset = expandedControlLeadingInset
        self.expandedControlTrailingInset = expandedControlTrailingInset
        self.onPageChange = onPageChange
        self.loadPreview = loadPreview
        self._carouselPosition = State(initialValue: CGFloat(currentPage.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 10) {
            if isExpanded {
                pagePicker
                    .offset(x: isPhone ? 0 : (expandedControlLeadingInset - expandedControlTrailingInset) / 2)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            pageCapsule
                .offset(x: isExpanded ? (expandedControlLeadingInset - expandedControlTrailingInset) / 2 : 0)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.width
                } action: { width in
                    availableControlWidth = width
                }
        }
        .onChange(of: currentPage) { _, page in
            guard totalPages > 0, dragStartPosition == nil, !isScrubbing,
                  (1 ... totalPages).contains(page) else { return }
            stopCoast()
            carouselPosition = CGFloat(page)
        }
        .onChange(of: totalPages) { _, total in
            guard total > 0 else { return }
            stopCoast()
            carouselPosition = CGFloat(clampedPage(currentPage))
        }
        .onDisappear {
            expansionID = UUID()
            isClosing = false
            setPageBordersVisible(false)
        }
    }

    private var pageCapsule: some View {
        Button(action: toggleExpanded) {
            VStack(spacing: 5) {
                Text("\(displayedPage) / \(totalPages)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .modifier(ReaderGlassLabelAppearance())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())

                progressBar
            }
            .frame(width: pageControlWidth, height: pageControlHeight)
        }
        .modifier(ReaderGlassButtonAppearance())
        .buttonBorderShape(.capsule)
        .onGeometryChange(for: CGFloat.self) { geometry in
            // Preserve the original glass button's padding in both states.
            geometry.size.width - pageControlWidth
        } action: { width in
            if !isExpanded {
                buttonStyleWidth = max(0, width)
            }
        }
        .accessibilityLabel(AppLocalization.format("페이지 %d, 전체 %d페이지", displayedPage, totalPages))
        .accessibilityHint(AppLocalization.text(isExpanded ? "페이지 목록 접기" : "페이지 목록 펼치기"))
    }

    private var pageControlWidth: CGFloat {
        guard isExpanded, availableControlWidth > 0 else {
            return isPhone ? progressBarWidth + 12 : 144
        }
        return max(0, expandedPageControlWidth - buttonStyleWidth)
    }

    private var expandedPageControlWidth: CGFloat {
        max(0, availableControlWidth - expandedControlLeadingInset - expandedControlTrailingInset)
    }

    private var previewStripWidth: CGFloat {
        isPhone ? availableControlWidth : max(0, expandedPageControlWidth - 4)
    }

    private var previewSlotWidth: CGFloat {
        max(1, (previewStripWidth - 6 * cardSpacing) / (5 + 2 * visibleEdgeCardFraction))
    }

    private var pickerHeight: CGFloat {
        let heights = previewImages.keys
            .filter { abs($0 - displayedPage) <= 3 }
            .map { pageCardSize(for: $0, slotWidth: previewSlotWidth).height }
        let placeholderHeight = min(maximumCardHeight, previewSlotWidth / 0.7)
        return max(heights.max() ?? 0, placeholderHeight) + 10
    }

    private func pageCardSize(for page: Int, slotWidth: CGFloat) -> CGSize {
        let image = previewImages[page]
        let ratio: CGFloat
        if let image, image.size.width > 0, image.size.height > 0 {
            ratio = image.size.width / image.size.height
        } else {
            ratio = 0.7
        }
        let width = min(slotWidth, maximumCardHeight * ratio)
        return CGSize(width: width, height: width / ratio)
    }

    private func toggleExpanded() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        stopCoastAndCommit()
        dragStartPosition = nil
        pageDragAxis = nil
        interruptedCoastInGesture = false
        isScrubbing = false
        let shouldExpand = !isExpanded || isClosing
        let expectedExpansion = UUID()
        expansionID = expectedExpansion
        isClosing = !shouldExpand
        if shouldExpand {
            carouselPosition = CGFloat(clampedPage(currentPage))
            setPageBordersVisible(false)
            withAnimation(.spring(response: 0.42, dampingFraction: 0.78), completionCriteria: .removed) {
                isExpanded = true
            } completion: {
                guard expansionID == expectedExpansion, isExpanded, !isClosing else { return }
                setPageBordersVisible(true)
            }
        } else {
            // Finish removing the border before starting the card's downward movement.
            withAnimation(.linear(duration: 0.06), completionCriteria: .removed) {
                showsPageBorders = false
            } completion: {
                guard expansionID == expectedExpansion, isClosing else { return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    isExpanded = false
                }
                isClosing = false
            }
        }
    }

    private func setPageBordersVisible(_ visible: Bool) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showsPageBorders = visible
        }
    }

    private func scrubGesture(in width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isExpanded, totalPages > 1, width > 0 else { return }
                if !isScrubbing {
                    stopCoast()
                    dragStartPosition = nil
                    interruptedCoastInGesture = false
                    isScrubbing = true
                }
                let fraction = min(max((value.location.x - 6) / width, 0), 1)
                let progress = isRightToLeft ? 1 - fraction : fraction
                let page = clampedPage(Int((1 + progress * CGFloat(totalPages - 1)).rounded()))
                if page != displayedPage {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                carouselPosition = CGFloat(page)
            }
            .onEnded { _ in
                guard isScrubbing else { return }
                let page = displayedPage
                isScrubbing = false
                select(page)
            }
    }

    private var pagePicker: some View {
        GeometryReader { geometry in
            if totalPages > 0 {
                // Five complete cards plus 35% of the next card at each fading edge.
                let stripWidth = min(geometry.size.width, previewStripWidth)
                let cardWidth = max(1, (stripWidth - 6 * cardSpacing) / (5 + 2 * visibleEdgeCardFraction))
                let cardStep = cardWidth + cardSpacing
                let fadeWidth = max(0, (stripWidth - (5 * cardWidth + 4 * cardSpacing)) / 2)
                let fadeFraction = min(0.49, fadeWidth / max(stripWidth, 1))
                let position = min(max(carouselPosition, 1), CGFloat(totalPages))
                let firstPage = max(1, Int(position.rounded(.down)) - 4)
                let lastPage = min(totalPages, Int(position.rounded(.up)) + 4)

                ZStack(alignment: .bottom) {
                    ForEach(firstPage ... lastPage, id: \.self) { page in
                        let distance = CGFloat(page) - position

                        pageCard(page, width: cardWidth)
                            .offset(x: distance * cardStep * directionSign)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHidden(abs(distance) >= 2.5)
                            .accessibilityAction { select(page) }
                    }
                }
                .frame(width: stripWidth, height: geometry.size.height, alignment: .bottom)
                .mask(LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: fadeFraction),
                    .init(color: .black, location: 1 - fadeFraction),
                    .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing))
                .contentShape(Rectangle())
                .gesture(pageDragGesture(in: stripWidth, cardStep: cardStep, centerPosition: position))
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .frame(height: pickerHeight)
        .clipped()
        // Move the complete strip as one layer during the expand/collapse transition.
        .compositingGroup()
        .task(id: displayedPage) {
            await loadPreviewWindow(around: displayedPage)
        }
        .onDisappear {
            stopCoastAndCommit()
            dragStartPosition = nil
            pageDragAxis = nil
            interruptedCoastInGesture = false
            isScrubbing = false
        }
        .accessibilityLabel("페이지 선택기")
    }

    private func pageCard(_ page: Int, width: CGFloat) -> some View {
        let isCentered = page == displayedPage
        let size = pageCardSize(for: page, slotWidth: width)
        let shape = RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
        let borderWidth = 1 / max(displayScale, 1)

        return Group {
            if let image = previewImages[page] {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .transition(.identity)
            } else {
                Text("\(page)")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .transition(.identity)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(AppTheme.surface, in: shape)
        .overlay(alignment: .bottom) {
            Text("\(page)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isCentered ? AppTheme.accentFill : Color.black.opacity(0.65), in: .capsule)
                .padding(.bottom, 5)
        }
        .overlay {
            shape.strokeBorder(.black, lineWidth: borderWidth)
                .opacity(showsPageBorders ? 1 : 0)
        }
        // Clip the image and its border together to exactly the same outer curve.
        .clipShape(shape)
        // Keep the image, backing, number and border in the same moving layer.
        .compositingGroup()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.format("페이지 %d", page))
        .accessibilityAddTraits(isCentered ? .isSelected : [])
    }

    @MainActor
    private func loadPreviewWindow(around center: Int) async {
        guard totalPages > 0, let loadPreview else { return }
        // Let a fast swipe or scrub settle before issuing new image requests.
        do {
            try await Task.sleep(nanoseconds: 150_000_000)
        } catch { return }
        guard !Task.isCancelled else { return }
        let pages = (max(1, center - previewPreloadRadius) ... min(totalPages, center + previewPreloadRadius))
        previewImages = previewImages.filter { pages.contains($0.key) }

        if previewImages[center] == nil, let image = await loadPreview(center) {
            guard !Task.isCancelled else { return }
            previewImages[center] = image
        }
        let remaining = pages.filter { $0 != center }.sorted {
            abs($0 - center) == abs($1 - center) ? $0 < $1 : abs($0 - center) < abs($1 - center)
        }
        for index in stride(from: 0, to: remaining.count, by: 2) {
            guard !Task.isCancelled else { return }
            let left = remaining[index]
            let right = index + 1 < remaining.count ? remaining[index + 1] : 0
            async let leftImage = previewImageIfNeeded(left, loader: loadPreview)
            async let rightImage = previewImageIfNeeded(right, loader: loadPreview)
            let images = await (leftImage, rightImage)
            guard !Task.isCancelled else { return }
            if let image = images.0 { previewImages[left] = image }
            if let image = images.1 { previewImages[right] = image }
        }
    }

    @MainActor
    private func previewImageIfNeeded(_ page: Int, loader: (Int) async -> UIImage?) async -> UIImage? {
        guard !Task.isCancelled, (1 ... totalPages).contains(page), previewImages[page] == nil else { return nil }
        return await loader(page)
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            let thumbInset: CGFloat = isExpanded ? 6 : 0
            let width = max(geometry.size.width - thumbInset * 2, 0)
            let progress = isExpanded
                ? CGFloat(displayedPage - 1) / CGFloat(max(totalPages - 1, 1))
                : CGFloat(displayedPage) / CGFloat(max(totalPages, 1))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ReaderGlassLabelAppearance.foregroundColor.opacity(0.3))
                    .frame(height: 3)
                Capsule()
                    .fill(ReaderGlassLabelAppearance.foregroundColor)
                    .frame(width: progress * width, height: 3)
                    .offset(x: isRightToLeft ? (1 - progress) * width : 0)
                Circle()
                    .fill(ReaderGlassLabelAppearance.foregroundColor)
                    .frame(width: 12, height: 12)
                    .offset(x: (isRightToLeft ? 1 - progress : progress) * width - 6)
                    .opacity(isExpanded ? 1 : 0)
            }
            .frame(width: width, height: geometry.size.height)
            .padding(.horizontal, thumbInset)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .highPriorityGesture(scrubGesture(in: width), including: isExpanded ? .all : .none)
        }
        .frame(width: isExpanded ? max(0, pageControlWidth - 32) : progressBarWidth,
               height: isExpanded ? 12 : 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("페이지 선택기")
        .accessibilityValue(AppLocalization.format("페이지 %d, 전체 %d페이지", displayedPage, totalPages))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(clampedPage(displayedPage + 1))
            case .decrement: select(clampedPage(displayedPage - 1))
            @unknown default: break
            }
        }
    }

    private func select(_ page: Int) {
        guard totalPages > 0, (1 ... totalPages).contains(page) else { return }

        stopCoast()
        dragStartPosition = nil
        interruptedCoastInGesture = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            carouselPosition = CGFloat(page)
        }

        notifyPageChange(page)
    }

    private func notifyPageChange(_ page: Int) {
        guard page != currentPage else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        onPageChange(page)
    }

    private func coast(to page: Int) {
        stopCoast()
        dragStartPosition = nil
        interruptedCoastInGesture = false

        let start = carouselPosition
        let end = CGFloat(page)
        let pageDistance = Double(abs(end - start))
        let duration = min(1.8, 0.22 + 0.25 * sqrt(pageDistance))
        let startedAt = CACurrentMediaTime()

        coastTask = Task { @MainActor in
            while !Task.isCancelled {
                let progress = min((CACurrentMediaTime() - startedAt) / duration, 1)
                let easedProgress = 1 - pow(1 - progress, 3)
                carouselPosition = start + (end - start) * CGFloat(easedProgress)
                if progress >= 1 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }

            guard !Task.isCancelled else { return }
            carouselPosition = end
            coastTask = nil
            notifyPageChange(page)
        }
    }

    private func stopCoast() {
        coastTask?.cancel()
        coastTask = nil
    }

    private func stopCoastAndCommit() {
        guard coastTask != nil else { return }
        stopCoast()
        let page = clampedPage(Int(carouselPosition.rounded()))
        carouselPosition = CGFloat(page)
        notifyPageChange(page)
    }

    private func pageDragGesture(in width: CGFloat, cardStep: CGFloat, centerPosition: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartPosition == nil {
                    interruptedCoastInGesture = coastTask != nil
                    stopCoast()
                    dragStartPosition = carouselPosition
                    pageDragAxis = nil
                }
                guard let start = dragStartPosition else { return }
                if pageDragAxis == nil {
                    let horizontalDistance = abs(value.translation.width)
                    let verticalDistance = abs(value.translation.height)
                    guard max(horizontalDistance, verticalDistance) >= 6 else { return }
                    pageDragAxis = verticalDistance > horizontalDistance ? .vertical : .horizontal
                }
                guard pageDragAxis == .horizontal else { return }
                let position = start - value.translation.width / cardStep * directionSign
                carouselPosition = min(max(position, 1), CGFloat(totalPages))
            }
            .onEnded { value in
                defer { pageDragAxis = nil }
                if pageDragAxis == .vertical {
                    let distance = value.translation.height
                    let projectedDistance = value.predictedEndTranslation.height
                    if distance >= 44 || (distance >= 12 && projectedDistance >= 80) {
                        guard isExpanded, !isClosing else { return }
                        select(clampedPage(Int(carouselPosition.rounded())))
                        toggleExpanded()
                    } else {
                        select(clampedPage(Int(carouselPosition.rounded())))
                    }
                    return
                }
                if abs(value.translation.width) < 6, abs(value.translation.height) < 6 {
                    if interruptedCoastInGesture {
                        select(clampedPage(Int(carouselPosition.rounded())))
                        return
                    }
                    let tappedPosition = centerPosition + (value.location.x - width / 2) / cardStep * directionSign
                    select(clampedPage(Int(tappedPosition.rounded())))
                    return
                }
                interruptedCoastInGesture = false
                let momentum = (value.predictedEndTranslation.width - value.translation.width) / cardStep * directionSign
                let projectedPosition = carouselPosition - momentum
                let page = clampedPage(Int(projectedPosition.rounded()))
                coast(to: page)
            }
    }

    private func clampedPage(_ page: Int) -> Int {
        min(max(page, 1), max(totalPages, 1))
    }
}

#Preview {
    ZStack {
        AppTheme.background.ignoresSafeArea()
        PageStripView(currentPage: .constant(5), totalPages: 24, onPageChange: { _ in })
            .padding(.bottom, 50)
    }
}
