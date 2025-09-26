import SwiftUI

struct PageStripView: View {
    @Binding var currentPage: Int
    let totalPages: Int
    let onPageChange: (Int) -> Void

    @State private var isExpanded = false
    @State private var scrollPosition: Int? = nil
    @State private var isScrolling = false
    @State private var hasUserScrolled = false

    private let haptics = UIImpactFeedbackGenerator(style: .medium)
    private let pageStripHeight: CGFloat = 90
    private let pageWidth: CGFloat = 45
    private let centerPageWidth: CGFloat = 60

    var body: some View {
        VStack(spacing: 16) {
            // Expandable page strip
            if isExpanded {
                naturalPageStrip
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.8, anchor: .bottom).combined(with: .opacity)
                    ))
            }

            // Main page indicator capsule
            pageCapsule
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isExpanded)
        .onAppear {
            if scrollPosition == nil {
                scrollPosition = currentPage
            }
        }
    }

    private var pageCapsule: some View {
        Button(action: toggleExpansion) {
            HStack(spacing: 12) {
                // Page text
                Text("\(currentPage) / \(totalPages)")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .animation(.easeOut(duration: 0.2), value: currentPage)

                // Progress indicator
                progressBar

                // Expand/collapse indicator
                Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .animation(.easeInOut(duration: 0.3), value: isExpanded)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(capsuleBackground)
            .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
    }

    private var naturalPageStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: -8) {
                    ForEach(1...totalPages, id: \.self) { pageNumber in
                        naturalPageItem(pageNumber: pageNumber, proxy: proxy)
                            .id(pageNumber)
                    }
                }
                .padding(.horizontal, 50)
                .scrollTargetLayout()
            }
            .scrollBounceBehavior(.automatic)
            .frame(height: pageStripHeight)
            .gesture(
                DragGesture()
                    .onChanged { _ in
                        if !hasUserScrolled {
                            print("👆 USER STARTED SCROLLING")
                            hasUserScrolled = true
                        }
                    }
            )
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ScrollOffsetKey.self, value: proxy.frame(in: .named("scrollArea")).minX)
                }
            )
            .onPreferenceChange(ScrollOffsetKey.self) { offset in
                print("📊 SCROLL OFFSET CHANGED: \(offset) | isExpanded: \(isExpanded)")
                detectCenterPage(scrollOffset: offset)
            }
            .coordinateSpace(name: "scrollArea")
            .onAppear {
                print("🎬 NATURAL PAGE STRIP APPEARED")
                // Scroll to current page when strip appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    print("📍 STRIP APPEARED - SCROLL TO CURRENT PAGE: \(currentPage)")
                    proxy.scrollTo(currentPage, anchor: UnitPoint.center)
                }
            }
        }
    }

    private func detectCenterPage(scrollOffset: CGFloat) {
        // Don't detect page changes when strip is not expanded
        guard isExpanded else {
            print("🚫 DETECT CENTER SKIPPED: strip not expanded")
            return
        }

        // Don't detect on initial appearance - only after user has actually scrolled
        guard hasUserScrolled else {
            print("🚫 DETECT CENTER SKIPPED: user hasn't scrolled yet")
            return
        }

        // Calculate which page is currently in the center
        let screenWidth: CGFloat = 744 // Use fixed width or get from geometry
        let itemWidth: CGFloat = 37 // pageWidth - spacing = 45 - 8
        let paddingOffset: CGFloat = 50

        // Calculate center page based on scroll offset
        let scrolledDistance = -scrollOffset - paddingOffset
        let centerPageFloat = (scrolledDistance + screenWidth/2) / itemWidth
        let centerPage = max(1, min(totalPages, Int(round(centerPageFloat))))

        print("🎯 DETECT CENTER: offset=\(scrollOffset), calculated=\(centerPage), current=\(currentPage)")

        if centerPage != currentPage && !isScrolling {
            print("✅ CENTER PAGE CHANGE: \(currentPage) -> \(centerPage)")
            UISelectionFeedbackGenerator().selectionChanged()
            onPageChange(centerPage)
        }
    }

    private func naturalPageItem(pageNumber: Int, proxy: ScrollViewProxy) -> some View {
        let isCurrent = pageNumber == currentPage
        let distance = abs(pageNumber - currentPage)

        return Button(action: {
            if pageNumber != currentPage {
                print("🔄 Tapped page: \(pageNumber)")
                UISelectionFeedbackGenerator().selectionChanged()
                onPageChange(pageNumber)

                // Scroll to center the tapped page
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        proxy.scrollTo(pageNumber, anchor: UnitPoint.center)
                    }
                }
            }
        }) {
            ZStack {
            // Main page rectangle
            RoundedRectangle(cornerRadius: 4)
                .fill(isCurrent ? .white.opacity(0.95) : .white.opacity(0.9))
                .frame(
                    width: isCurrent ? centerPageWidth : pageWidth,
                    height: isCurrent ? 80 : 60
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.white.opacity(0.6), lineWidth: 0.5)
                )
                .overlay(
                    Text("\(pageNumber)")
                        .font(.system(size: isCurrent ? 14 : 10, weight: .medium))
                        .foregroundStyle(isCurrent ? .black : .black.opacity(0.8))
                )
                .rotation3DEffect(
                    .degrees(isCurrent ? 0 : (pageNumber < currentPage ? -12 : 12)),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.6
                )
                .scaleEffect(isCurrent ? 1.0 : 0.85)
                .zIndex(isCurrent ? 100 : Double(50 - distance))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
            }
        }
        .buttonStyle(.plain)
    }

    private var progressBar: some View {
        ZStack(alignment: .leading) {
            // Background track
            Capsule()
                .fill(.white.opacity(0.3))
                .frame(width: 60, height: 4)

            // Progress fill
            Capsule()
                .fill(.white.opacity(0.8))
                .frame(width: CGFloat(currentPage) / CGFloat(totalPages) * 60, height: 4)
                .animation(.easeOut(duration: 0.2), value: currentPage)

            // Progress glow
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: CGFloat(currentPage) / CGFloat(totalPages) * 60, height: 4)
                .animation(.easeOut(duration: 0.2), value: currentPage)
        }
    }

    private var capsuleBackground: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(isExpanded ? 0.9 : 0.8)
            Capsule()
                .stroke(.white.opacity(isExpanded ? 0.4 : 0.3), lineWidth: isExpanded ? 1.0 : 0.5)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(isExpanded ? 0.25 : 0.2), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            if isExpanded {
                Capsule()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.08), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 50
                        )
                    )
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isExpanded)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isExpanded)
    }


    private func toggleExpansion() {
        haptics.impactOccurred()

        print("🔄 TOGGLE EXPANSION: \(isExpanded) -> \(!isExpanded) | currentPage: \(currentPage)")

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            isExpanded.toggle()
        }
    }

}

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        PageStripView(
            currentPage: .constant(5),
            totalPages: 24,
            onPageChange: { _ in }
        )
        .padding(.bottom, 50)
    }
}