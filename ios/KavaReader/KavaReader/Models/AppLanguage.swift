import Foundation

nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case korean = "ko"
    case english = "en"

    static let storageKey = "app_language"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "ko") ?? .korean
    }
}

nonisolated enum AppLocalization {
    static func text(_ key: String, language: AppLanguage = .current) -> String {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: AppLanguage.current.locale, arguments: arguments)
    }
}
