import Foundation
import HootKit

public enum FileWatcherError: Error {
    case cannotOpenDirectory(URL)
}

/// Watches a single top-level directory (non-recursive) and reports files
/// once they exist and have stopped changing size — so callers never see
/// a file that's still being written or downloaded.
public final class FileWatcher: FileWatching {
    public init() {}

    public var onNewFile: ((URL) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var knownEntries: Set<String> = []
    private var pendingStabilityChecks: [String: DispatchWorkItem] = [:]
    private var watchedFolder: URL?
    private let queue = DispatchQueue(label: "app.owl.filewatcher")

    private static let stabilityPollInterval: TimeInterval = 0.6
    private static let maxStabilityAttempts = 20

    public func start(watching folder: URL) throws {
        stop()

        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            throw FileWatcherError.cannotOpenDirectory(folder)
        }

        watchedFolder = folder
        knownEntries = Set((try? currentEntries(in: folder)) ?? [])
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.handleDirectoryChange()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
        }
        source.resume()
        self.source = source
    }

    public func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
        watchedFolder = nil
        knownEntries = []
        pendingStabilityChecks.values.forEach { $0.cancel() }
        pendingStabilityChecks = [:]
    }

    private func currentEntries(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path)
    }

    private func handleDirectoryChange() {
        guard let folder = watchedFolder, let entries = try? currentEntries(in: folder) else { return }
        let entrySet = Set(entries)
        let newNames = entrySet.subtracting(knownEntries)
        knownEntries = entrySet

        for name in newNames {
            scheduleStabilityCheck(for: folder.appendingPathComponent(name))
        }
    }

    private func scheduleStabilityCheck(for url: URL, previousSize: Int64? = nil, attempt: Int = 0) {
        let key = url.path
        pendingStabilityChecks[key]?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.checkStability(of: url, previousSize: previousSize, attempt: attempt)
        }
        pendingStabilityChecks[key] = work
        queue.asyncAfter(deadline: .now() + Self.stabilityPollInterval, execute: work)
    }

    private func checkStability(of url: URL, previousSize: Int64?, attempt: Int) {
        pendingStabilityChecks.removeValue(forKey: url.path)

        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard !FileAnalyzer.isIgnored(url) else { return }

        let currentSize = fileSize(at: url.path)

        if attempt > 0, previousSize != nil, previousSize == currentSize {
            onNewFile?(url)
        } else if attempt < Self.maxStabilityAttempts {
            scheduleStabilityCheck(for: url, previousSize: currentSize, attempt: attempt + 1)
        } else {
            onNewFile?(url)
        }
    }

    private func fileSize(at path: String) -> Int64? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return (attrs[.size] as? NSNumber)?.int64Value
    }

    deinit {
        stop()
    }
}
