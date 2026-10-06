import Foundation

/// Read declared categories only. Titles, filenames and prose are never guessed as genres.
nonisolated enum EmbeddedMetadataReader {
    static func epub(_ metadata: EpubXML?) -> LibraryPlusMetadata {
        guard let metadata else { return LibraryPlusMetadata(summary: "", genres: [], tags: []) }
        var genres: [String] = []
        var tags: [String] = []
        for node in metadata.children {
            // dc:subject is the standard EPUB subject/category field. Preserve compound labels.
            if node.name == "subject" { genres.append(node.plainText) }
            guard node.name == "meta", node.attributes["refines"] == nil else { continue }
            let key = (node.attributes["property"] ?? node.attributes["name"] ?? "").lowercased()
            let value = node.attributes["content"] ?? node.plainText
            switch key {
            case "genre", "genres", "calibre:genre": genres += list(value)
            case "tag", "tags", "keywords", "calibre:tags": tags += list(value)
            default: break
            }
        }
        let summary = metadata.children.first { $0.name == "description" }?.plainText ?? ""
        return LibraryPlusMetadata(summary: summary, genres: genres, tags: tags)
    }

    static func comic(_ archive: ComicArchive) throws -> LibraryPlusMetadata {
        // Prefer the conventional root entry; accept one nested entry for folder-wrapped archives.
        let matches = archive.entries.filter {
            ($0.name as NSString).lastPathComponent.lowercased() == "comicinfo.xml"
        }
        let entry = matches.first { !$0.name.contains("/") } ?? (matches.count == 1 ? matches.first : nil)
        guard let entry else { return LibraryPlusMetadata(summary: "", genres: [], tags: []) }
        return try comicXML(archive.resource(named: entry.name))
    }

    static func comicXML(_ data: Data) throws -> LibraryPlusMetadata {
        let root = try EpubXML.parse(data)
        guard root.name.lowercased() == "comicinfo" else { throw EpubPublication.Failure.invalid }
        func value(_ name: String) -> String {
            root.children.first { $0.name.lowercased() == name.lowercased() }?.plainText ?? ""
        }
        return LibraryPlusMetadata(summary: value("Summary"), genres: list(value("Genre")), tags: list(value("Tags")))
    }

    private static func list(_ value: String) -> [String] {
        value.components(separatedBy: CharacterSet(charactersIn: ",;\n"))
    }
}
