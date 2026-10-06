import Combine
import CryptoKit
import Foundation

// MARK: - Reader Mode Options

enum HorizontalDisplayMode: String, CaseIterable, Identifiable {
    case singlePage = "single_page"
    case doublePage = "double_page"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .singlePage: return AppLocalization.text("한 페이지")
        case .doublePage: return AppLocalization.text("두 페이지")
        }
    }

    var pageCount: Int { self == .doublePage ? 2 : 1 }
}

/// 페이지 진행 방향
enum ScrollDirection: String, CaseIterable, Identifiable {
    case leftToRight = "horizontal" // 기존 설정값과 동작을 유지
    case rightToLeft = "horizontal_rtl"
    case vertical

    // MARK: Internal

    var id: String { rawValue }

    var isHorizontal: Bool { self != .vertical }

    var isRightToLeft: Bool { self == .rightToLeft }

    var directionSymbol: String {
        switch self {
        case .leftToRight: return "arrow.right"
        case .rightToLeft: return "arrow.left"
        case .vertical: return "arrow.down"
        }
    }

    var nextDirection: ScrollDirection {
        switch self {
        case .leftToRight: return .rightToLeft
        case .rightToLeft: return .vertical
        case .vertical: return .leftToRight
        }
    }

    var displayName: String {
        switch self {
        case .leftToRight: return AppLocalization.text("왼쪽 → 오른쪽")
        case .rightToLeft: return AppLocalization.text("오른쪽 → 왼쪽")
        case .vertical: return AppLocalization.text("세로 스크롤")
        }
    }

    var description: String {
        switch self {
        case .leftToRight: return AppLocalization.text("왼쪽으로 넘기면 다음 페이지")
        case .rightToLeft: return AppLocalization.text("오른쪽으로 넘기면 다음 페이지")
        case .vertical: return AppLocalization.text("웹툰 스타일 (위아래로 스크롤)")
        }
    }
}

// MARK: - Reader Settings Model

/// 읽기 설정을 관리하는 클래스
@MainActor
class ReaderSettings: ObservableObject {
    static let extendPageEdgesKey = "reader_extend_page_edges"
    static let tapEdgesToTurnPagesKey = "reader_tap_edges_to_turn_pages"
    static let horizontalDisplayModeKey = "reader_horizontal_display_mode"
    static let firstPageAloneKey = "reader_first_page_alone"
    static let pageCurlEnabledKey = "reader_page_curl_enabled"

    // MARK: Lifecycle

    // MARK: - Initialization

    init() {
        // UserDefaults에서 설정 로드
        if let scrollDirectionRaw = UserDefaults.standard.string(forKey: "reader_scroll_direction"),
           let scrollDirection = ScrollDirection(rawValue: scrollDirectionRaw)
        {
            self.scrollDirection = scrollDirection
        } else {
            scrollDirection = .leftToRight // 기본값
        }
        horizontalDisplayMode = UserDefaults.standard.string(forKey: Self.horizontalDisplayModeKey)
            .flatMap(HorizontalDisplayMode.init(rawValue:)) ?? .singlePage
        firstPageAlone = UserDefaults.standard.bool(forKey: Self.firstPageAloneKey)
        pageCurlEnabled = UserDefaults.standard.object(forKey: Self.pageCurlEnabledKey) as? Bool ?? true
        extendPageEdges = UserDefaults.standard.object(forKey: Self.extendPageEdgesKey) as? Bool ?? true
        tapEdgesToTurnPages = UserDefaults.standard.object(forKey: Self.tapEdgesToTurnPagesKey) as? Bool ?? true
    }

    // MARK: Internal

    // MARK: - Published Properties

    @Published var scrollDirection: ScrollDirection {
        didSet { saveSettings() }
    }

    @Published var horizontalDisplayMode: HorizontalDisplayMode {
        didSet { UserDefaults.standard.set(horizontalDisplayMode.rawValue, forKey: Self.horizontalDisplayModeKey) }
    }

    @Published var firstPageAlone: Bool {
        didSet { UserDefaults.standard.set(firstPageAlone, forKey: Self.firstPageAloneKey) }
    }

    @Published var pageCurlEnabled: Bool {
        didSet { UserDefaults.standard.set(pageCurlEnabled, forKey: Self.pageCurlEnabledKey) }
    }

    @Published var extendPageEdges: Bool {
        didSet { UserDefaults.standard.set(extendPageEdges, forKey: Self.extendPageEdgesKey) }
    }

    @Published var tapEdgesToTurnPages: Bool {
        didSet { UserDefaults.standard.set(tapEdgesToTurnPages, forKey: Self.tapEdgesToTurnPagesKey) }
    }

    // MARK: Private

    // MARK: - Methods

    /// 설정을 UserDefaults에 저장
    private func saveSettings() {
        UserDefaults.standard.set(scrollDirection.rawValue, forKey: "reader_scroll_direction")
    }
}

// MARK: - Singleton Instance

extension ReaderSettings {
    /// 앱 전체에서 사용할 싱글톤 인스턴스
    static let shared = ReaderSettings()
}

/// Stores this series' optional reader preferences without changing the global defaults.
@MainActor
final class SeriesReaderSettings: ObservableObject {
    private struct SavedSettings: Codable {
        let usesGlobalSettings: Bool
        let scrollDirection: String
        let horizontalDisplayMode: String?
        let firstPageAlone: Bool?
        let pageCurlEnabled: Bool?
        let extendPageEdges: Bool
        let tapEdgesToTurnPages: Bool
    }

    @Published var usesGlobalSettings: Bool {
        didSet { save() }
    }

    @Published var scrollDirection: ScrollDirection {
        didSet {
            hasLocalSettings = true
            save()
        }
    }

    @Published var horizontalDisplayMode: HorizontalDisplayMode {
        didSet {
            hasLocalSettings = true
            save()
        }
    }

    @Published var firstPageAlone: Bool {
        didSet {
            hasLocalSettings = true
            save()
        }
    }

    @Published var pageCurlEnabled: Bool {
        didSet {
            hasLocalSettings = true
            save()
        }
    }

    @Published var extendPageEdges: Bool {
        didSet {
            hasLocalSettings = true
            save()
        }
    }

    @Published var tapEdgesToTurnPages: Bool {
        didSet {
            hasLocalSettings = true
            save()
        }
    }

    init(identity: String, series: LibrarySeries, global: ReaderSettings) {
        let seriesID = series.kavitaSeriesId.map(String.init) ?? series.id.uuidString
        let digest = SHA256.hash(data: Data("\(identity)|\(seriesID)".utf8))
            .map { String(format: "%02x", $0) }.joined()
        let key = "reader_series_settings_\(digest)"
        storageKey = key

        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(SavedSettings.self, from: data)
        {
            usesGlobalSettings = saved.usesGlobalSettings
            scrollDirection = ScrollDirection(rawValue: saved.scrollDirection) ?? global.scrollDirection
            horizontalDisplayMode = saved.horizontalDisplayMode
                .flatMap(HorizontalDisplayMode.init(rawValue:)) ?? global.horizontalDisplayMode
            firstPageAlone = saved.firstPageAlone ?? global.firstPageAlone
            pageCurlEnabled = saved.pageCurlEnabled ?? global.pageCurlEnabled
            extendPageEdges = saved.extendPageEdges
            tapEdgesToTurnPages = saved.tapEdgesToTurnPages
            hasLocalSettings = true
        } else {
            usesGlobalSettings = true
            scrollDirection = global.scrollDirection
            horizontalDisplayMode = global.horizontalDisplayMode
            firstPageAlone = global.firstPageAlone
            pageCurlEnabled = global.pageCurlEnabled
            extendPageEdges = global.extendPageEdges
            tapEdgesToTurnPages = global.tapEdgesToTurnPages
            hasLocalSettings = false
        }
    }

    func setUsesGlobalSettings(_ value: Bool, global: ReaderSettings) {
        guard usesGlobalSettings != value else { return }
        if !value && !hasLocalSettings {
            scrollDirection = global.scrollDirection
            horizontalDisplayMode = global.horizontalDisplayMode
            firstPageAlone = global.firstPageAlone
            pageCurlEnabled = global.pageCurlEnabled
            extendPageEdges = global.extendPageEdges
            tapEdgesToTurnPages = global.tapEdgesToTurnPages
            hasLocalSettings = true
        }
        usesGlobalSettings = value
    }

    func localDirection(or global: ReaderSettings) -> ScrollDirection {
        hasLocalSettings ? scrollDirection : global.scrollDirection
    }

    private let storageKey: String
    private var hasLocalSettings: Bool

    private func save() {
        let settings = SavedSettings(usesGlobalSettings: usesGlobalSettings,
                                     scrollDirection: scrollDirection.rawValue,
                                     horizontalDisplayMode: horizontalDisplayMode.rawValue,
                                     firstPageAlone: firstPageAlone,
                                     pageCurlEnabled: pageCurlEnabled,
                                     extendPageEdges: extendPageEdges,
                                     tapEdgesToTurnPages: tapEdgesToTurnPages)
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
