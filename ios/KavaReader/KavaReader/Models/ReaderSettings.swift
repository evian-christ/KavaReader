import Foundation
import Combine

// MARK: - Reader Mode Options

/// 페이지 맞춤 모드
enum PageFitMode: String, CaseIterable, Identifiable {
    case fitWidth = "fit_width"      // 너비에 맞춤
    case fitHeight = "fit_height"    // 높이에 맞춤
    case fitScreen = "fit_screen"    // 화면에 맞춤
    case original = "original"       // 원본 크기

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fitWidth: return "너비에 맞춤"
        case .fitHeight: return "높이에 맞춤"
        case .fitScreen: return "화면에 맞춤"
        case .original: return "원본 크기"
        }
    }

    var description: String {
        switch self {
        case .fitWidth: return "페이지 너비를 화면에 맞춤"
        case .fitHeight: return "페이지 높이를 화면에 맞춤"
        case .fitScreen: return "페이지 전체를 화면에 맞춤"
        case .original: return "페이지 원본 크기로 표시"
        }
    }
}

/// 스크롤 방향
enum ScrollDirection: String, CaseIterable, Identifiable {
    case horizontal = "horizontal"   // 가로 스크롤 (기본)
    case vertical = "vertical"       // 세로 스크롤

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

    // MARK: - Published Properties

    @Published var pageFitMode: PageFitMode {
        didSet { saveSettings() }
    }

    @Published var scrollDirection: ScrollDirection {
        didSet { saveSettings() }
    }


    // MARK: - Initialization

    init() {
        // UserDefaults에서 설정 로드
        if let pageFitModeRaw = UserDefaults.standard.string(forKey: "reader_page_fit_mode"),
           let pageFitMode = PageFitMode(rawValue: pageFitModeRaw) {
            self.pageFitMode = pageFitMode
        } else {
            self.pageFitMode = .fitWidth // 기본값
        }

        if let scrollDirectionRaw = UserDefaults.standard.string(forKey: "reader_scroll_direction"),
           let scrollDirection = ScrollDirection(rawValue: scrollDirectionRaw) {
            self.scrollDirection = scrollDirection
        } else {
            self.scrollDirection = .horizontal // 기본값
        }

    }

    // MARK: - Methods

    /// 설정을 UserDefaults에 저장
    private func saveSettings() {
        UserDefaults.standard.set(pageFitMode.rawValue, forKey: "reader_page_fit_mode")
        UserDefaults.standard.set(scrollDirection.rawValue, forKey: "reader_scroll_direction")
    }

    /// 모든 설정을 기본값으로 리셋
    func resetToDefaults() {
        pageFitMode = .fitWidth
        scrollDirection = .horizontal
    }
}

// MARK: - Singleton Instance

extension ReaderSettings {
    /// 앱 전체에서 사용할 싱글톤 인스턴스
    static let shared = ReaderSettings()
}