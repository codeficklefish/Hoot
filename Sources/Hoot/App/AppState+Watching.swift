import Foundation
import AppKit
import HootKit
import HootPlatformMac

/// Choosing a folder and noticing what arrives in it.
///
/// Split out of `AppState` so each part of the app's behaviour can be read
/// on its own; the state itself stays in one place.
extension AppState {

    /// Opens the folder chooser.
    ///
    /// Two things make this fiddly for a menu bar app, and both caused the
    /// panel to appear but ignore clicks:
    ///
    /// 1. Hoot runs as an accessory, so it is not the active application.
    ///    An inactive app's panel opens without taking key focus, and the
    ///    first click is spent activating rather than selecting.
    /// 2. `runModal()` starts a nested modal loop *inside* the popover's own
    ///    event-tracking loop. The two compete for events, so clicks on the
    ///    sidebar and file list get swallowed intermittently.
    ///
    /// Activating first, then opening on the next run-loop pass (by which
    /// point the popover has closed), and using the asynchronous `begin`
    /// instead of a nested modal loop, avoids both.
    func presentFolderPicker() {
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor [weak self] in
            guard let self else { return }

            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.prompt = "Watch Folder"
            panel.message = "Choose a folder for Hoot to watch."
            panel.directoryURL = self.watchedFolder
                ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

            panel.begin { response in
                guard response == .OK, let url = panel.url else { return }
                Task { @MainActor in
                    self.beginWatching(url)
                }
            }

            // Ensure the panel is frontmost and keyboard-focused even though
            // the app only just became active.
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func beginWatching(_ folder: URL, alreadyAuthorized: Bool = false) {
        // Only record a grant the user just made; restoring one shouldn't
        // rewrite the bookmark it came from.
        if !alreadyAuthorized {
            folderAccess.remember(folder)
        }

        watcher.stop()
        watchedFolder = folder
        detectedFiles = []
        classifications = [:]
        plan = nil
        lastNotifiedCount = 0
        notifications.clearPending()

        do {
            try watcher.start(watching: folder)
        } catch {
            report(
                UserFacingIssue(
                    title: "Couldn't watch “\(folder.lastPathComponent)”.",
                    suggestion: "Choose the folder again, or pick a different one."
                ),
                underlying: error
            )
            watchedFolder = nil
            folderAccess.forget()
            return
        }

        scanExistingFiles(in: folder)

        MacPlatform.makeAIProvider(for: settings)?.prewarm()
        precomputePlan()
    }

    func scanExistingFiles(in folder: URL) {
        isScanning = true
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in contents where !FileAnalyzer.isIgnored(url) {
            ingest(url: url)
        }
        isScanning = false
    }

    func ingest(url: URL) {
        guard let item = FileAnalyzer.analyze(url) else { return }
        guard !detectedFiles.contains(where: { $0.url == item.url }) else { return }

        detectedFiles.append(item)
        detectedFiles.sort { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        scheduleWaitingNotification()

        Task {
            do {
                let result = try await classifier.classify(item)
                await MainActor.run {
                    self.classifications[item.id] = result
                }
            } catch {
                await MainActor.run {
                    self.report(
                        UserFacingIssue(
                            title: "Couldn't work out what “\(item.filename)” is.",
                            suggestion: "It will still appear, sorted by file type.",
                            severity: .warning
                        ),
                        underlying: error
                    )
                }
            }
        }
    }
}
