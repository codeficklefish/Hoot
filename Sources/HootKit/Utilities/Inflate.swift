import Foundation

/// DEFLATE decompression (RFC 1951) in plain Swift.
///
/// Zip members — and therefore `.docx`, `.xlsx` and every archive Hoot looks
/// inside — are DEFLATE streams. Apple supplies a decoder; Windows does not
/// ship one Swift can reach without pulling in zlib as a system dependency.
/// Rather than make each platform solve it, the engine carries its own: about
/// two hundred lines, no dependencies, identical output everywhere.
///
/// Correctness is checked against Apple's implementation in the verification
/// suite, over real archives rather than synthetic ones.
public struct Inflate: ArchiveInflating {
    public init() {}

    public func inflate(_ deflated: Data, expectedSize: Int) -> Data? {
        guard !deflated.isEmpty, expectedSize > 0 else { return nil }
        var reader = BitReader(deflated)
        var output = [UInt8]()
        output.reserveCapacity(expectedSize)

        while true {
            guard let isFinal = reader.bit(), let kind = reader.bits(2) else { return nil }

            switch kind {
            case 0:
                guard Self.copyStoredBlock(&reader, into: &output, limit: expectedSize) else { return nil }
            case 1:
                guard Self.expand(&reader, into: &output, limit: expectedSize,
                                  literals: Self.fixedLiterals, distances: Self.fixedDistances)
                else { return nil }
            case 2:
                guard let (literals, distances) = Self.readDynamicTables(&reader),
                      Self.expand(&reader, into: &output, limit: expectedSize,
                                  literals: literals, distances: distances)
                else { return nil }
            default:
                return nil   // 3 is reserved and means the stream is corrupt
            }

            if isFinal == 1 { break }
            // A stream claiming more data than it should is treated as corrupt
            // rather than trusted; the caller already bounded expectedSize.
            if output.count > expectedSize { return nil }
        }

        return Data(output)
    }

    // MARK: - Block kinds

    private static func copyStoredBlock(
        _ reader: inout BitReader, into output: inout [UInt8], limit: Int
    ) -> Bool {
        reader.alignToByte()
        guard let length = reader.bits(16), let inverse = reader.bits(16) else { return false }
        // The length is stored twice, the second time inverted.
        guard length == (~inverse & 0xFFFF) else { return false }
        guard output.count + length <= limit else { return false }
        for _ in 0..<length {
            guard let byte = reader.byte() else { return false }
            output.append(byte)
        }
        return true
    }

    /// Reads the Huffman tables a dynamic block defines for itself.
    private static func readDynamicTables(_ reader: inout BitReader) -> (Huffman, Huffman)? {
        guard let hlit = reader.bits(5), let hdist = reader.bits(5), let hclen = reader.bits(4)
        else { return nil }
        let literalCount = hlit + 257
        let distanceCount = hdist + 1
        let codeLengthCount = hclen + 4

        // The lengths of the code-length alphabet arrive in this fixed order.
        var codeLengths = [Int](repeating: 0, count: 19)
        for index in 0..<codeLengthCount {
            guard let value = reader.bits(3) else { return nil }
            codeLengths[codeLengthOrder[index]] = value
        }
        guard let codeLengthTable = Huffman(lengths: codeLengths) else { return nil }

        // Those codes then encode the lengths of the literal and distance trees,
        // with three run-length escapes.
        var lengths = [Int]()
        lengths.reserveCapacity(literalCount + distanceCount)
        while lengths.count < literalCount + distanceCount {
            guard let symbol = codeLengthTable.decode(&reader) else { return nil }
            switch symbol {
            case 0...15:
                lengths.append(symbol)
            case 16:                        // repeat the previous length 3-6 times
                guard let extra = reader.bits(2), let previous = lengths.last else { return nil }
                lengths.append(contentsOf: repeatElement(previous, count: 3 + extra))
            case 17:                        // a run of zeros, 3-10
                guard let extra = reader.bits(3) else { return nil }
                lengths.append(contentsOf: repeatElement(0, count: 3 + extra))
            case 18:                        // a longer run of zeros, 11-138
                guard let extra = reader.bits(7) else { return nil }
                lengths.append(contentsOf: repeatElement(0, count: 11 + extra))
            default:
                return nil
            }
        }
        guard lengths.count == literalCount + distanceCount else { return nil }

        guard let literals = Huffman(lengths: Array(lengths[0..<literalCount])),
              let distances = Huffman(lengths: Array(lengths[literalCount...]))
        else { return nil }
        return (literals, distances)
    }

    /// The main loop: literals are emitted, and length/distance pairs copy text
    /// that has already been written.
    private static func expand(
        _ reader: inout BitReader, into output: inout [UInt8], limit: Int,
        literals: Huffman, distances: Huffman
    ) -> Bool {
        while true {
            guard let symbol = literals.decode(&reader) else { return false }

            if symbol < 256 {
                guard output.count < limit else { return false }
                output.append(UInt8(symbol))
                continue
            }
            if symbol == 256 { return true }          // end of block

            let lengthIndex = symbol - 257
            guard lengthIndex < lengthBase.count,
                  let lengthExtraBits = reader.bits(lengthExtra[lengthIndex])
            else { return false }
            let length = lengthBase[lengthIndex] + lengthExtraBits

            guard let distanceSymbol = distances.decode(&reader),
                  distanceSymbol < distanceBase.count,
                  let distanceExtraBits = reader.bits(distanceExtra[distanceSymbol])
            else { return false }
            let distance = distanceBase[distanceSymbol] + distanceExtraBits

            // A back-reference must point at text already produced.
            guard distance > 0, distance <= output.count,
                  output.count + length <= limit else { return false }

            // Copied one byte at a time on purpose: runs may overlap, which is
            // how DEFLATE encodes repetition.
            var source = output.count - distance
            for _ in 0..<length {
                output.append(output[source])
                source += 1
            }
        }
    }

    // MARK: - Tables (RFC 1951, section 3.2.5)

    private static let lengthBase = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
    ]
    private static let lengthExtra = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
    ]
    private static let distanceBase = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
        257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
    ]
    private static let distanceExtra = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
        7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
    ]
    private static let codeLengthOrder = [
        16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
    ]

    /// The tree a fixed-Huffman block uses without stating it.
    private static let fixedLiterals: Huffman = {
        var lengths = [Int](repeating: 8, count: 288)
        for i in 144..<256 { lengths[i] = 9 }
        for i in 256..<280 { lengths[i] = 7 }
        return Huffman(lengths: lengths)!
    }()

    private static let fixedDistances: Huffman = {
        Huffman(lengths: [Int](repeating: 5, count: 30))!
    }()
}

// MARK: - Reading a bit at a time

/// DEFLATE packs bits least-significant first within each byte.
private struct BitReader {
    private let data: [UInt8]
    private var byteIndex = 0
    private var bitIndex = 0

    init(_ data: Data) { self.data = [UInt8](data) }

    mutating func bit() -> Int? {
        guard byteIndex < data.count else { return nil }
        let value = (Int(data[byteIndex]) >> bitIndex) & 1
        bitIndex += 1
        if bitIndex == 8 { bitIndex = 0; byteIndex += 1 }
        return value
    }

    mutating func bits(_ count: Int) -> Int? {
        guard count >= 0 else { return nil }
        var value = 0
        for shift in 0..<count {
            guard let next = bit() else { return nil }
            value |= next << shift
        }
        return value
    }

    mutating func alignToByte() {
        if bitIndex != 0 { bitIndex = 0; byteIndex += 1 }
    }

    mutating func byte() -> UInt8? {
        guard bitIndex == 0, byteIndex < data.count else { return nil }
        defer { byteIndex += 1 }
        return data[byteIndex]
    }
}

// MARK: - Canonical Huffman decoding

/// Decodes symbols from the canonical code the block's lengths describe.
///
/// Stored as counts-per-length plus symbols in order, which is enough to walk
/// the code bit by bit without building a tree.
private struct Huffman {
    private var countPerLength: [Int]
    private var symbols: [Int]

    init?(lengths: [Int]) {
        let maximumBits = 15
        countPerLength = [Int](repeating: 0, count: maximumBits + 1)
        for length in lengths where length > 0 {
            guard length <= maximumBits else { return nil }
            countPerLength[length] += 1
        }

        // Symbols are stored grouped by code length, ascending within a group —
        // which is exactly what canonical Huffman means.
        symbols = [Int](repeating: 0, count: lengths.filter { $0 > 0 }.count)
        var cursor = [Int](repeating: 0, count: maximumBits + 1)
        var running = 0
        for length in 1...maximumBits {
            cursor[length] = running
            running += countPerLength[length]
        }
        for (symbol, length) in lengths.enumerated() where length > 0 {
            symbols[cursor[length]] = symbol
            cursor[length] += 1
        }
    }

    func decode(_ reader: inout BitReader) -> Int? {
        var code = 0
        var first = 0
        var index = 0
        for length in 1...15 {
            guard let next = reader.bit() else { return nil }
            code |= next
            let count = countPerLength[length]
            if code - first < count {
                return symbols[index + (code - first)]
            }
            index += count
            first = (first + count) << 1
            code <<= 1
        }
        return nil
    }
}
