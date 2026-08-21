import Foundation

/// A read-only peek inside zip containers, used to identify what a file is.
///
/// Covers both plain `.zip` archives and the Office formats that are zips
/// underneath (`.xlsx`). Only what's needed to *recognize* a file: list the
/// entries, and pull out one small member. Deliberately not a general zip
/// library — no writing, no encryption, no spanned archives.
///
/// Everything here treats the file as hostile input: sizes declared in the
/// archive's own headers are capped before allocating, so a crafted zip can't
/// make Hoot exhaust memory.
public struct ZipReader {

    /// Refuse to inflate any single member larger than this.
    private static let maximumMemberSize = 4 * 1024 * 1024
    /// Stop walking the directory after this many entries.
    private static let maximumEntries = 2_000
    /// The end-of-central-directory record lives in the last 64KB + comment.
    private static let eocdSearchWindow = 66 * 1024

    public struct Entry {
        public let name: String
        public let compressionMethod: UInt16
        public let compressedSize: Int
        public let uncompressedSize: Int
        public let localHeaderOffset: Int
    }

    private let data: Data
    /// Supplied by the platform: macOS has the Compression framework, Windows
    /// has zlib. Parsing the archive is pure Foundation; only the DEFLATE step
    /// needs help.
    private let inflater: ArchiveInflating

    public init?(url: URL, inflater: ArchiveInflating) {
        // Memory-map so listing a large archive doesn't read it all in.
        guard let mapped = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        self.data = mapped
        self.inflater = inflater
    }

    public init(data: Data, inflater: ArchiveInflating) {
        self.data = data
        self.inflater = inflater
    }

    /// Entries listed in the central directory, or empty if this isn't a zip.
    public func entries() -> [Entry] {
        guard let directoryStart = centralDirectoryOffset() else { return [] }

        var entries: [Entry] = []
        var cursor = directoryStart

        while cursor + 46 <= data.count, entries.count < Self.maximumEntries {
            guard readUInt32(at: cursor) == 0x0201_4b50 else { break } // central file header

            let method = readUInt16(at: cursor + 10)
            let compressed = Int(readUInt32(at: cursor + 20))
            let uncompressed = Int(readUInt32(at: cursor + 24))
            let nameLength = Int(readUInt16(at: cursor + 28))
            let extraLength = Int(readUInt16(at: cursor + 30))
            let commentLength = Int(readUInt16(at: cursor + 32))
            let localOffset = Int(readUInt32(at: cursor + 42))

            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else { break }
            let name = String(decoding: data[nameStart..<nameStart + nameLength], as: UTF8.self)

            entries.append(
                Entry(
                    name: name,
                    compressionMethod: method,
                    compressedSize: compressed,
                    uncompressedSize: uncompressed,
                    localHeaderOffset: localOffset
                )
            )

            cursor = nameStart + nameLength + extraLength + commentLength
        }

        return entries
    }

    /// Inflates a single member by exact name. Returns nil when absent,
    /// unsupported, or larger than the safety cap.
    public func contents(of entryName: String) -> Data? {
        guard let entry = entries().first(where: { $0.name == entryName }) else { return nil }
        guard entry.uncompressedSize > 0,
              entry.uncompressedSize <= Self.maximumMemberSize else { return nil }

        // The local header repeats the name/extra lengths, which may differ
        // from the central directory's, so the payload offset is read here.
        let header = entry.localHeaderOffset
        guard header + 30 <= data.count, readUInt32(at: header) == 0x0403_4b50 else { return nil }
        let nameLength = Int(readUInt16(at: header + 26))
        let extraLength = Int(readUInt16(at: header + 28))
        let payload = header + 30 + nameLength + extraLength
        guard payload + entry.compressedSize <= data.count else { return nil }

        let compressed = data[payload..<payload + entry.compressedSize]

        switch entry.compressionMethod {
        case 0: // stored
            return Data(compressed)
        case 8: // deflate
            return inflater.inflate(Data(compressed), expectedSize: entry.uncompressedSize)
        default:
            return nil
        }
    }


    /// Locates the central directory by scanning backwards for the
    /// end-of-central-directory signature.
    private func centralDirectoryOffset() -> Int? {
        guard data.count >= 22 else { return nil }
        let lowerBound = max(0, data.count - Self.eocdSearchWindow)
        var cursor = data.count - 22

        while cursor >= lowerBound {
            if readUInt32(at: cursor) == 0x0605_4b50 {
                let offset = Int(readUInt32(at: cursor + 16))
                return offset < data.count ? offset : nil
            }
            cursor -= 1
        }
        return nil
    }

    // MARK: - Little-endian reads (bounds-checked)

    private func readUInt16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        let base = data.startIndex + offset
        return UInt16(data[base]) | UInt16(data[base + 1]) << 8
    }

    private func readUInt32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        let base = data.startIndex + offset
        return UInt32(data[base])
            | UInt32(data[base + 1]) << 8
            | UInt32(data[base + 2]) << 16
            | UInt32(data[base + 3]) << 24
    }
}
