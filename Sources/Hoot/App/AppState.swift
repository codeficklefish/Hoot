import Foundation
import AppKit
import HootKit
import HootPlatformMac

/// The app's single source of truth: which folder is being watched, what's
/// been discovered in it, the classification for each file, and the history of
/// moves already made. UI reads from here; it never touches the watcher,
/// analyzer, classifier, or organizer directly.
@MainActor
final class AppState: ObservableObject {
    @Published var watchedFolder: URL?
    @Published var detectedFiles: [FileItem] = []
    @Published var classifications: [UUID: ClassificationResult] = [:]
    @Published var isScanning = false

    /// The current proposal awaiting review. Nothing has moved while this is set.
    @Published var plan: OrganizationPlan?
    @Published var batches: [OperationBatch] = []
    @Published var lastMessage: String?
    /// Problems worth telling the user about. Kept short: the most recent
    /// few, newest first.
    @Published var issues: [UserFacingIssue] = []

    /// True while a model is working out how files group together.
    @Published var isAnalyzing = false

    /// Identifies the file set and preferences the current plan was built
    /// from, so an unchanged folder never pays for analysis twice.
    var planSignature: String?
    /// The single in-flight analysis, shared by the background pass and any
    /// user request that arrives while it's running.
    var analysisTask: Task<Void, Never>?
    /// Category refinements keyed by file signature, so adding one file
    /// doesn't re-analyze the ones already understood.
    var refinementCache: [String: ClassificationResult] = [:]
    @Published var settings: AISettings {
        didSet { settings.save() }
    }
    /// Folder names the user has corrected before.
    @Published var folderPreferences: FolderPreferences
    /// What Hoot has learned from folders the user organized themselves.
    @Published var learned: LearnedClassifier?
    /// Leave-one-out accuracy of `learned`, shown so its worth is visible.
    @Published var learnedAccuracy: Double?
    /// Times the user overruled Hoot, fed back into the personal model.
    @Published var corrections = CorrectionLog.load()
    /// Text read from inside each file, so the review screen can show *why*
    /// a suggestion was made rather than asking for blind trust.
    @Published var evidence: [UUID: String] = [:]
    /// What the AI layer is currently able to do, for display in Settings.
    @Published var providerStatus: String = "Checking…"

    /// True until the user has been through the first-run screen.
    @Published var needsOnboarding: Bool

    static let onboardingKey = "onboarding.completed"

    let watcher: FileWatching
    let classifier: FileClassifier
    let planner = OrganizationPlanner()
    let organizer: Organizer
    let history: OperationHistory
    let notifications = NotificationService()
    let folderAccess = WatchedFolderAccess()

    /// Coalesces a burst of arriving files into a single notification.
    var notificationTask: Task<Void, Never>?
    /// How many files had already been announced, so we only speak up when
    /// the pile actually grows.
    var lastNotifiedCount = 0

    init(
        watcher: FileWatching = MacPlatform.makeFileWatcher(),
        classifier: FileClassifier = RuleBasedClassifier(),
        organizer: Organizer = Organizer(),
        history: OperationHistory = OperationHistory()
    ) {
        self.watcher = watcher
        self.classifier = classifier
        self.organizer = organizer
        self.history = history
        self.batches = history.batches
        self.settings = AISettings.load()
        self.folderPreferences = FolderPreferences.load()
        self.learned = LearnedClassifier.load()
        self.needsOnboarding = !UserDefaults.standard.bool(forKey: Self.onboardingKey)

        watcher.onNewFile = { [weak self] url in
            Task { @MainActor in
                self?.ingest(url: url)
            }
        }

        Task { await refreshProviderStatus() }

        // Resume the folder granted on a previous launch. Under the sandbox
        // this is the only way back in without asking the user again.
        if let remembered = folderAccess.restore() {
            beginWatching(remembered, alreadyAuthorized: true)
        }
    }

    /// Groups current files by project or category, for the compact summary
    /// shown in the menu bar (e.g. "Thesis  4").
    var summaryByCategory: [(label: String, count: Int)] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for file in detectedFiles {
            let label = classifications[file.id]?.project ?? classifications[file.id]?.category ?? "Sorting…"
            if counts[label] == nil { order.append(label) }
            counts[label, default: 0] += 1
        }
        return order.map { ($0, counts[$0] ?? 0) }
    }

    var canUndo: Bool { history.mostRecentUndoable != nil }

    /// How a non-SwiftUI surface asks for a window.
    ///
    /// SwiftUI's `openWindow` lives in the environment, which AppKit code — the
    /// island panel — has no way to reach. The app scene hands this over at
    /// launch so there is one way in rather than a second window system.
    var presentWindow: ((String) -> Void)?

    // MARK: - Watching

    // MARK: - Review

    // MARK: - Organizing

}
