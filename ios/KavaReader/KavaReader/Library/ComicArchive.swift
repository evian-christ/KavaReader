import Foundation
import zlib

/// Reads image entries without expanding an entire comic into the library.
nonisolated struct ComicArchive: Sendable {
    struct Entry: Codable, Sendable {
        let name: String
        let offset: Int
        let compressedSize: Int
        let size: Int
        let method: Int
        let crc: UInt32
    }

    enum Failure: Error, LocalizedError {
        case invalid, unsupported, tooLarge, noImages
        var errorDescription: String? {
            switch self {
            case .invalid: AppLocalization.text("손상된 만화 파일입니다.")
            case .unsupported: AppLocalization.text("암호화 또는 ZIP64 압축은 지원하지 않습니다.")
            case .tooLarge: AppLocalization.text("페이지 이미지가 너무 큽니다.")
            case .noImages: AppLocalization.text("압축 파일에 읽을 수 있는 이미지가 없습니다.")
            }
        }
    }

    let data: Data
    let entries: [Entry]

    init(url: URL, includeAllEntries: Bool = false) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        self.data = data
        guard data.count >= 22 else { throw Failure.invalid }
        func word(_ offset: Int, _ count: Int) throws -> UInt32 {
            guard offset >= 0, offset + count <= data.count else { throw Failure.invalid }
            return (0..<count).reduce(UInt32(0)) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
        }
        var end: Int?
        for position in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            if try word(position, 4) == 0x06054b50,
               position + 22 + Int(try word(position + 20, 2)) == data.count {
                end = position
                break
            }
        }
        guard let end else { throw Failure.invalid }
        guard try word(end + 4, 2) == 0, try word(end + 6, 2) == 0,
              try word(end + 8, 2) == word(end + 10, 2) else { throw Failure.unsupported }
        let count = Int(try word(end + 10, 2))
        let centralOffset = Int(try word(end + 16, 4))
        let centralSize = Int(try word(end + 12, 4))
        guard count != 65_535, centralOffset != Int(UInt32.max), centralSize != Int(UInt32.max) else {
            throw Failure.unsupported
        }
        guard centralOffset + centralSize <= end else { throw Failure.invalid }
        var position = centralOffset
        var images: [Entry] = []
        for _ in 0..<count {
            guard try word(position, 4) == 0x02014b50 else { throw Failure.invalid }
            let flags = try word(position + 8, 2)
            let method = Int(try word(position + 10, 2))
            let nameSize = Int(try word(position + 28, 2))
            let extraSize = Int(try word(position + 30, 2))
            let commentSize = Int(try word(position + 32, 2))
            let next = position + 46 + nameSize + extraSize + commentSize
            guard next <= centralOffset + centralSize else { throw Failure.invalid }
            let nameData = data.subdata(in: position + 46..<position + 46 + nameSize)
            guard let name = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) else {
                throw Failure.invalid
            }
            let ext = (name as NSString).pathExtension.lowercased()
            if (includeAllEntries || ["jpg", "jpeg", "png", "gif", "webp", "bmp", "heic"].contains(ext)),
               !name.hasSuffix("/"),
               !name.hasPrefix("__MACOSX/"), !(name as NSString).lastPathComponent.hasPrefix(".") {
                guard flags & 1 == 0, [0, 8].contains(method) else { throw Failure.unsupported }
                let offset = Int(try word(position + 42, 4))
                let compressed = Int(try word(position + 20, 4))
                let size = Int(try word(position + 24, 4))
                guard offset != Int(UInt32.max), compressed != Int(UInt32.max), size != Int(UInt32.max) else {
                    throw Failure.unsupported
                }
                images.append(Entry(name: name, offset: offset, compressedSize: compressed, size: size,
                                    method: method, crc: try word(position + 16, 4)))
            }
            position = next
        }
        guard !images.isEmpty else { throw Failure.noImages }
        entries = images.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func imageData(at index: Int) throws -> Data {
        guard entries.indices.contains(index) else { throw Failure.invalid }
        return try entryData(entries[index])
    }

    func resource(named name: String) throws -> Data {
        guard let entry = entries.first(where: { $0.name == name }) else { throw Failure.invalid }
        return try entryData(entry)
    }

    private func entryData(_ entry: Entry) throws -> Data {
        guard entry.size >= 0, entry.size <= 100 * 1024 * 1024, entry.compressedSize <= 100 * 1024 * 1024 else { throw Failure.tooLarge }
        let offset = entry.offset
        guard offset >= 0, offset + 30 <= data.count,
              Array(data[offset..<offset + 4]) == [0x50, 0x4b, 0x03, 0x04] else { throw Failure.invalid }
        let nameSize = Int(data[offset + 26]) | Int(data[offset + 27]) << 8
        let extraSize = Int(data[offset + 28]) | Int(data[offset + 29]) << 8
        let start = offset + 30 + nameSize + extraSize
        guard start + entry.compressedSize <= data.count else { throw Failure.invalid }
        let input = data.subdata(in: start..<start + entry.compressedSize)
        let output: Data
        if entry.method == 0 {
            guard input.count == entry.size else { throw Failure.invalid }
            output = input
        } else {
            var inflated = Data(count: max(1, entry.size))
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw Failure.invalid
            }
            defer { inflateEnd(&stream) }
            let status = input.withUnsafeBytes { source in
                inflated.withUnsafeMutableBytes { destination in
                    stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
                    stream.avail_in = uInt(input.count)
                    stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(max(1, entry.size))
                    return inflate(&stream, Z_FINISH)
                }
            }
            guard status == Z_STREAM_END, Int(stream.total_out) == entry.size,
                  Int(stream.total_in) == input.count else { throw Failure.invalid }
            output = Data(inflated.prefix(entry.size))
        }
        let checksum = output.withUnsafeBytes { buffer in
            crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(output.count))
        }
        guard UInt32(checksum) == entry.crc else { throw Failure.invalid }
        return output
    }
}
