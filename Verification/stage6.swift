import Foundation
import HootKit
import HootPlatformMac

/// Starting and stopping the watcher must not accumulate open file
/// descriptors.
///
/// Worth a check of its own because the mistake is invisible by inspection and
/// silent at runtime. `DispatchSource` cancellation is asynchronous, so the
/// descriptor is closed by the cancel handler rather than by `stop` — and a
/// handler that reads the descriptor back off the watcher finds it already
/// reset, closes nothing, and leaves the old directory held open. Hoot is a
/// menu bar app that runs for days, so a leak per folder change accumulates.
func stage6(sandbox: URL, rawCheck: @escaping (String, Bool, String) -> Void) {
    print("\n[the watcher releases the descriptors it opens]")

    // /dev/fd lists this process's own open descriptors.
    func openDescriptors() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd"))?.count ?? -1
    }

    let watcher = FileWatcher()

    // One cycle before measuring, so any one-off setup is already counted.
    try? watcher.start(watching: sandbox)
    watcher.stop()
    Thread.sleep(forTimeInterval: 0.2)

    let before = openDescriptors()
    for _ in 0..<40 {
        try? watcher.start(watching: sandbox)
        watcher.stop()
    }
    // Cancel handlers run on the watcher's queue; let them drain.
    Thread.sleep(forTimeInterval: 0.5)
    let after = openDescriptors()

    rawCheck(
        "40 start/stop cycles leak no descriptors",
        before > 0 && after - before <= 2,
        "(open descriptors went \(before) -> \(after))"
    )

    // Listing /dev/fd is only meaningful if it reflects this process at all.
    rawCheck("descriptor count is readable", before > 0, "(/dev/fd returned \(before))")
}
