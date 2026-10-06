import Foundation

nonisolated struct EpubSection: Codable, Hashable, Sendable {
    let path: String
    let title: String
}

nonisolated struct EpubLocation: Codable, Hashable, Sendable {
    let section: Int
    let fraction: Double
}

nonisolated struct EpubPublication: Codable, Hashable, Sendable {
    let title: String
    let author: String
    let sections: [EpubSection]
    let resources: [String: String]
    let coverPath: String?
    let fixedLayout: Bool
    var embeddedMetadata: LibraryPlusMetadata? = nil

    enum Failure: Error, LocalizedError {
        case invalid, encrypted, unsafePath
        var errorDescription: String? {
            switch self {
            case .invalid: AppLocalization.text("EPUB 본문 구조를 읽을 수 없습니다.")
            case .encrypted: AppLocalization.text("암호화된 EPUB은 지원하지 않습니다.")
            case .unsafePath: AppLocalization.text("EPUB 내부 파일 경로가 올바르지 않습니다.")
            }
        }
    }

    init(archive: ComicArchive) throws {
        let names = Set(archive.entries.map(\.name))
        guard names.contains("mimetype"),
              String(data: try archive.resource(named: "mimetype"), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "application/epub+zip"
        else { throw Failure.invalid }
        if names.contains("META-INF/encryption.xml") {
            let encryption = try EpubXML.parse(archive.resource(named: "META-INF/encryption.xml"))
            if !encryption.descendants("EncryptedData").isEmpty { throw Failure.encrypted }
        }
        let container = try EpubXML.parse(archive.resource(named: "META-INF/container.xml"))
        guard let packageHref = container.descendants("rootfile").first?.attributes["full-path"] else { throw Failure.invalid }
        let packagePath = try Self.path(packageHref, relativeTo: "")
        let package = try EpubXML.parse(archive.resource(named: packagePath))
        guard package.name == "package", let manifest = package.children.first(where: { $0.name == "manifest" }),
              let spine = package.children.first(where: { $0.name == "spine" }) else { throw Failure.invalid }
        let folder = (packagePath as NSString).deletingLastPathComponent
        var byID: [String: (path: String, mime: String, properties: Set<String>)] = [:]
        var resources: [String: String] = [:]
        for item in manifest.children where item.name == "item" {
            guard let id = item.attributes["id"], let href = item.attributes["href"],
                  let mime = item.attributes["media-type"] else { throw Failure.invalid }
            let path = try Self.path(href, relativeTo: folder)
            guard names.contains(path), byID[id] == nil else { throw Failure.invalid }
            let properties = Set((item.attributes["properties"] ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init))
            byID[id] = (path, mime, properties)
            resources[path] = mime
        }
        var sections: [EpubSection] = []
        for reference in spine.children where reference.name == "itemref" && reference.attributes["linear"] != "no" {
            guard let id = reference.attributes["idref"], let item = byID[id],
                  ["application/xhtml+xml", "text/html", "image/svg+xml"].contains(item.mime) else { throw Failure.invalid }
            sections.append(EpubSection(path: item.path, title: (item.path as NSString).lastPathComponent))
        }
        guard !sections.isEmpty else { throw Failure.invalid }
        let navigation = byID.values.first { $0.properties.contains("nav") } ??
            spine.attributes["toc"].flatMap { byID[$0] }
        if let navigation, let document = try? EpubXML.parse(archive.resource(named: navigation.path)) {
            let base = (navigation.path as NSString).deletingLastPathComponent
            var labels: [String: String] = [:]
            for link in document.descendants("a") {
                if let href = link.attributes["href"], let path = try? Self.path(href, relativeTo: base) {
                    let label = link.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !label.isEmpty, labels[path] == nil { labels[path] = label }
                }
            }
            for point in document.descendants("navPoint") {
                if let src = point.children.first(where: { $0.name == "content" })?.attributes["src"],
                   let path = try? Self.path(src, relativeTo: base),
                   let label = point.children.first(where: { $0.name == "navLabel" })?.plainText.trimmingCharacters(in: .whitespacesAndNewlines),
                   !label.isEmpty, labels[path] == nil { labels[path] = label }
            }
            sections = sections.map { EpubSection(path: $0.path, title: labels[$0.path] ?? $0.title) }
        }
        let metadata = package.children.first { $0.name == "metadata" }
        let title = metadata?.children.first { $0.name == "title" }?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let authors = metadata?.children.filter { $0.name == "creator" }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
        let oldCoverID = metadata?.children.first { $0.name == "meta" && $0.attributes["name"] == "cover" }?.attributes["content"]
        self.coverPath = byID.values.first { $0.properties.contains("cover-image") }?.path ?? oldCoverID.flatMap { byID[$0]?.path }
        self.embeddedMetadata = EmbeddedMetadataReader.epub(metadata)
        self.title = title
        self.author = authors.filter { !$0.isEmpty }.joined(separator: ", ")
        self.resources = resources
        self.sections = sections
        self.fixedLayout = metadata?.children.contains {
            $0.name == "meta" && $0.attributes["property"] == "rendition:layout" &&
                $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == "pre-paginated"
        } ?? false
    }

    /// Resolves package references inside this archive, never filesystem or remote URLs.
    static func path(_ href: String, relativeTo folder: String) throws -> String {
        guard !href.contains("\\"), let components = URLComponents(string: href),
              components.scheme == nil, components.host == nil, !href.hasPrefix("/") else { throw Failure.unsafePath }
        guard let decoded = components.percentEncodedPath.removingPercentEncoding, !decoded.contains("\\"), !decoded.contains("\0") else { throw Failure.unsafePath }
        var parts = folder.split(separator: "/").map(String.init)
        for part in decoded.split(separator: "/").map(String.init) {
            if part == "." { continue }
            if part == ".." {
                guard !parts.isEmpty else { throw Failure.unsafePath }
                parts.removeLast()
            } else { parts.append(part) }
        }
        guard !parts.isEmpty else { throw Failure.unsafePath }
        return parts.joined(separator: "/")
    }
}

/// Only package XML is parsed here; publication scripts and external entities are never evaluated.
nonisolated struct EpubXML: Sendable {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [EpubXML] = []

    var plainText: String { text + children.map(\.plainText).joined() }

    func descendants(_ name: String) -> [EpubXML] {
        children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) }
    }

    static func parse(_ data: Data) throws -> EpubXML {
        guard data.count <= 4 * 1024 * 1024,
              let xml = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16),
              !xml.localizedCaseInsensitiveContains("<!DOCTYPE"), !xml.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw EpubPublication.Failure.invalid
        }
        let delegate = Builder()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { throw EpubPublication.Failure.invalid }
        return root
    }

    private nonisolated final class Builder: NSObject, XMLParserDelegate {
        var stack: [EpubXML] = []
        var root: EpubXML?
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            if stack.count >= 64 { parser.abortParsing(); return }
            let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
            stack.append(EpubXML(name: name, attributes: attributeDict))
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if !stack.isEmpty { stack[stack.count - 1].text += string }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            guard let node = stack.popLast() else { return }
            if stack.isEmpty { root = node }
            else { stack[stack.count - 1].children.append(node) }
        }
    }
}
