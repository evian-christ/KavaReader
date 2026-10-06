import Observation
import SwiftUI

/// Presets provide readable dark and light palettes for the app and reader.
enum ThemePalette: String, CaseIterable, Identifiable {
    case graphite, forest, midnight, plum, mocha, pureBlack, classicWhite, ocean, paper

    var id: String { rawValue }
    var name: String {
        switch self {
        case .forest: "깊은 숲"
        case .midnight: "고요한 밤"
        case .plum: "자두빛 저녁"
        case .mocha: "따뜻한 모카"
        case .graphite: "흑연"
        case .pureBlack: "퓨어 블랙"
        case .classicWhite: "클래식 화이트"
        case .ocean: "깊은 바다"
        case .paper: "크림 페이퍼"
        }
    }

    // Main, accent, filled button, text. Surfaces are derived from the main color.
    var hexColors: [UInt32] {
        switch self {
        case .forest: [0x17221B, 0x58A878, 0x2A6A47, 0xEEF4EF]
        case .midnight: [0x171E2B, 0x83B5EA, 0x315B87, 0xEDF3FA]
        case .plum: [0x251C29, 0xC99BD4, 0x70497D, 0xF7EFF8]
        case .mocha: [0x282019, 0xD3AB7D, 0x795734, 0xF7F0E6]
        case .graphite: [0x202124, 0xB2BDC9, 0x505C69, 0xF1F2F4]
        case .pureBlack: [0x000000, 0xC7C7CC, 0x343438, 0xF5F5F7]
        case .classicWhite: [0xF2F2F7, 0x005FCC, 0x005FCC, 0x1C1C1E]
        case .ocean: [0x102629, 0x6DC7C2, 0x236C69, 0xEAF7F5]
        case .paper: [0xF4EFE5, 0x80602F, 0x77542E, 0x342C22]
        }
    }

    var colorScheme: ColorScheme {
        self == .classicWhite || self == .paper ? .light : .dark
    }

    var buttonText: Color { colorScheme == .light ? .white : text }

    var background: Color { color(hexColors[0]) }
    var accent: Color { color(hexColors[1]) }
    var button: Color { color(hexColors[2]) }
    var text: Color { color(hexColors[3]) }
    var surface: Color {
        let hex = hexColors[0]
        // Light presets also derive a brighter surface from their main color.
        let whiteMix = colorScheme == .light ? 0.55 : 0.06
        return Color(red: channel(hex, shift: 16) * (1 - whiteMix) + whiteMix,
                     green: channel(hex, shift: 8) * (1 - whiteMix) + whiteMix,
                     blue: channel(hex, shift: 0) * (1 - whiteMix) + whiteMix)
    }

    private func color(_ hex: UInt32) -> Color {
        Color(red: channel(hex, shift: 16), green: channel(hex, shift: 8), blue: channel(hex, shift: 0))
    }

    private func channel(_ hex: UInt32, shift: UInt32) -> Double {
        Double((hex >> shift) & 0xFF) / 255
    }
}

@Observable
final class ThemeSettings {
    static let shared = ThemeSettings()
    private static let storageKey = "app_theme"

    var selected: ThemePalette {
        didSet { UserDefaults.standard.set(selected.rawValue, forKey: Self.storageKey) }
    }

    private init() {
        selected = ThemePalette(rawValue: UserDefaults.standard.string(forKey: Self.storageKey) ?? "") ?? .graphite
    }
}

// Reading the observable selection here also updates existing SwiftUI screens.
enum AppTheme {
    static var palette: ThemePalette { ThemeSettings.shared.selected }
    static var background: Color { palette.background }
    static var surface: Color { palette.surface }
    static var accent: Color { palette.accent }
    static var accentFill: Color { palette.button }
    static var text: Color { palette.text }
    static var buttonText: Color { palette.buttonText }
    static var secondaryText: Color { text.opacity(0.65) }
    static var tertiaryText: Color { text.opacity(0.4) }
    static var coverGradient: [Color] { [accentFill, surface] }
}
