import Combine
import Foundation

// MARK: - Reader Mode Options

/// 페이지 맞춤 모드 (현재는 너비에 맞춤만 지원)
enum PageFitMode: String, Identifiable {
    case fitWidth = "fit_width"

    // MARK: Internal

    var id: String { rawValue }
}

/// 스크롤 방향
enum ScrollDirection: String, CaseIterable, Identifiable {
    case horizontal // 가로 스크롤 (기본)
    case vertical // 세로 스크롤

    // MARK: Internal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .horizontal: return "좌우 넘기기"
        case .vertical: return "위아래 스크롤"
        }
    }

    var description: String {
        switch self {
        case .horizontal: return "일반 만화 스타일 (좌우로 페이지 넘기기)"
        case .vertical: return "웹툰 스타일 (위아래로 스크롤)"
        }
    }
}

// MARK: - Reader Settings Model

/// 읽기 설정을 관리하는 클래스
@MainActor
class ReaderSettings: ObservableObject {
    // MARK: Lifecycle

    // MARK: - Initialization

    init() {
        // UserDefaults에서 설정 로드
        if let scrollDirectionRaw = UserDefaults.standard.string(forKey: "reader_scroll_direction"),
           let scrollDirection = ScrollDirection(rawValue: scrollDirectionRaw)
        {
            self.scrollDirection = scrollDirection
        } else {
            scrollDirection = .horizontal // 기본값
        }
    }

    // MARK: Internal

    // MARK: - Published Properties

    @Published var scrollDirection: ScrollDirection {
        didSet { saveSettings() }
    }

    var pageFitMode: PageFitMode { .fitWidth }

    /// 모든 설정을 기본값으로 리셋
    func resetToDefaults() {
        scrollDirection = .horizontal
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
