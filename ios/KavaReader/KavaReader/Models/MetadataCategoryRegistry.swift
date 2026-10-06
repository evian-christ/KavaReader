import Foundation

nonisolated enum MetadataCategoryKind: String, Sendable {
    case genre, tag
}

/// Stable identities are independent of both the source spelling and the selected UI language.
nonisolated enum MetadataCategoryRegistry {
    struct Entry: Identifiable, Sendable {
        let id: String
        let englishName: String
        let localizedNames: [String: String]
        var aliases: [String] = []

        func name(language: AppLanguage) -> String {
            localizedNames[language.rawValue] ?? englishName
        }

        func storageID(kind: MetadataCategoryKind) -> String { "\(kind.rawValue):\(id)" }
    }

    struct Catalog: Sendable {
        let entries: [Entry]
        private let byID: [String: Entry]
        private let byName: [String: [String]]
        private let byEnglishName: [String: String]

        init(entries: [Entry]) {
            self.entries = entries.sorted { $0.id < $1.id }
            byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            var names: [String: Set<String>] = [:]
            var english: [String: String] = [:]
            for entry in entries {
                english[MetadataCategoryRegistry.normalized(entry.englishName)] = entry.id
                for name in [entry.englishName] + Array(entry.localizedNames.values) + entry.aliases {
                    names[MetadataCategoryRegistry.normalized(name), default: []].insert(entry.id)
                }
            }
            byName = names.mapValues { $0.sorted() }
            byEnglishName = english
        }

        func candidates(_ value: String, kind: MetadataCategoryKind) -> [Entry] {
            let key = MetadataCategoryRegistry.normalized(value)
            let prefix = kind.rawValue + ":"
            if key.hasPrefix(prefix), let entry = byID[String(key.dropFirst(prefix.count))] {
                return [entry]
            }
            // An exact source name is authoritative even if a translation elsewhere shares it.
            if let id = byEnglishName[key], let entry = byID[id] { return [entry] }
            return (byName[key] ?? []).compactMap { byID[$0] }
        }
    }

    // Add a locale to each entry's localizedNames to support another language. IDs stay unchanged.
    // Only explicit synonyms share an ID; equal translations alone never merge distinct concepts.
    static let catalog: Catalog = {
        let aliases = ["sci fi": "sci-fi", "science fiction": "sci-fi",
                       "vampire": "vampires", "zombie": "zombies"]
        let extraAliases: [String: [String]] = [
            "sci-fi": ["sf", "공상과학"], "adventure": ["어드벤처"],
            "mystery": ["미스테리"], "romance": ["연애"], "comedy": ["개그"],
            "slice of life": ["일상물"], "school": ["학원", "학원물", "school life"],
            "sports": ["sport"], "horror": ["호러"], "iyashikei": ["힐링", "힐링물", "치유물"],
        ]
        let names = MetadataLocalization.koreanNames
        let entries = names.keys.sorted().filter { aliases[$0] == nil }.map { key in
            Entry(id: key, englishName: key == "sci-fi" ? "Sci-Fi" : key.capitalized,
                  localizedNames: ["ko": names[key] ?? key],
                  aliases: aliases.filter { $0.value == key }.map(\.key) + (extraAliases[key] ?? []))
        }
        return Catalog(entries: entries)
    }()

    static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ").lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    static func candidates(_ value: String, kind: MetadataCategoryKind) -> [Entry] {
        catalog.candidates(value, kind: kind)
    }

    static func identity(_ value: String, kind: MetadataCategoryKind) -> String {
        let matches = candidates(value, kind: kind)
        if matches.count == 1 { return matches[0].storageID(kind: kind) }
        return "\(kind.rawValue):custom:\(normalized(value))"
    }

    static func storageValue(_ value: String, kind: MetadataCategoryKind) -> String {
        let matches = candidates(value, kind: kind)
        return matches.count == 1 ? matches[0].storageID(kind: kind)
            : value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func matchingName(_ value: String, kind: MetadataCategoryKind) -> String {
        let matches = candidates(value, kind: kind)
        return matches.count == 1 ? matches[0].englishName : value
    }

    static func cleaned(_ values: [String], kind: MetadataCategoryKind) -> [String] {
        var seen = Set<String>()
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(identity($0, kind: kind)).inserted }
    }

    static func contains(_ values: [String], value: String, kind: MetadataCategoryKind) -> Bool {
        let id = identity(value, kind: kind)
        return values.contains { identity($0, kind: kind) == id }
    }
}
