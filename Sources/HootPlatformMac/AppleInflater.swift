import Foundation
import Compression
import HootKit

/// DEFLATE via Apple's Compression framework.
///
/// The zip parsing itself is pure Foundation and lives in the engine; this is
/// the one step that needs a platform library. A Windows build supplies the
/// same protocol backed by zlib.
public struct AppleInflater: ArchiveInflating {
    public init() {}

    public func inflate(_ deflated: Data, expectedSize: Int) -> Data? {
        guard !deflated.isEmpty, expectedSize > 0 else { return nil }
        var output = Data(count: expectedSize)

        let written = output.withUnsafeMutableBytes { destination -> Int in
            guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return deflated.withUnsafeBytes { source -> Int in
                guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                // COMPRESSION_ZLIB is raw DEFLATE here, which is what zip
                // method 8 stores (no zlib wrapper).
                return compression_decode_buffer(
                    destinationBase, expectedSize,
                    sourceBase, deflated.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }

        guard written > 0 else { return nil }
        return output.prefix(written)
    }
}
