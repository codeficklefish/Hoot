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
    /// Whether folders are named after what files are about, or what they are.
    ///
    /// Changing this invalidates the current proposal rather than editing it:
    /// the two modes reach their answers by different routes, and a plan that
    /// is half one and half the other would be a third thing nobody chose.
    @Published var sortingMode: SortingMode = SortingMode.load() {
        didSet {
            guard oldValue != sortingMode else { return }
            sortingMode.save()
            plan = nil
            planSignature = nil
            Task { await buildPlan(force: true) }
        }
    }
    /// Folder names the user has corrected before.
    @Published var folderPreferences: FolderPreferences
    /// What Hoot has learned from folders the user organized themselves.
    @Published var learned: LearnedClassifier?
    /// Leave-one-out accuracy of `learned`, shown so its worth is visible.
    @Published var learnedAccuracy: Double?
    /// Times the user overruled Hoot, fed back into the personal model.
    @Published var corrections = CorrectionLog.load()
    /// What was read from inside each file, so the review screen can show
    /// *why* a suggestion was made rather than asking for blind trust.
    ///
    /// The whole `ExtractedEvidence` rather than just its text, because
    /// renaming turns on `isTextual`: words on a photographed receipt may
    /// become a filename, "appears to show: outdoor, sky" may not.
    @Published var evidence: [UUID: ExtractedEvidence] = [:]
    /// Why each proposed name was chosen, keyed by file, so a rename can be
    /// shown with its source rather than asserted.
    @Published var renameNotes: [UUID: String] = [:]
    /// Proposed names keyed by file signature. The value is itself optional
    /// so that a *refusal* is remembered too — without that, every scan
    /// re-asks the model about the files it has already declined to name.
    var renameCache: [String: ProposedName?] = [:]

    /// The folders the notch lists. Independent of `watchedFolder`: Hoot
    /// organizes one folder and reads as many as it is shown, and keeping
    /// those two apart is what lets the second be plural without touching
    /// the containment rule the first depends on.
    @Published var shelf = FileShelf()
    /// Guards against re-reading on every hover flicker. Also the instant
    /// every age on the panel is measured from — a fresh `Date()` per refresh
    /// meant no two renders were ever equal, so SwiftUI redrew every row of
    /// every folder on every published change, however little had moved.
    @Published var lastShelfRead: Date = .distantPast
    /// What the shelf last handed to something else, shown until dismissed.
    /// A handover is the one thing the panel does that has no visible result
    /// inside the panel, so it says so rather than appearing to do nothing.
    /// Tells the second click of a pair from the first, so a row can
    /// highlight on the first without waiting to find out. Not published: it
    /// is timing rather than content, and a redraw per click is exactly the
    /// cost this exists to remove. See `ClickPair`.
    var shelfClicks = ClickPair()

    @Published var shelfHandoff: String?
    /// Opening a window is the app's business, not the state's — `openWindow`
    /// is a SwiftUI environment value and exists only inside a scene. The app
    /// hands this in so the notch can send you to the review window without
    /// this type knowing what a window is.
    var openReviewWindow: (() -> Void)?

    /// What the AI layer is currently able to do, for display in Settings.
    @Published var providerStatus: String = "Checking…"

    /// True until the user has been through the first-run screen.
    @Published var needsOnboarding: Bool

    static let onboardingKey = "onboarding.completed"

    let watcher: FileWatching
    let classifier: RuleBasedClassifier
    let planner = OrganizationPlanner()
    let organizer: Organizer
    let history: OperationHistory
    let notifier: Notifying
    let folderAccess: FolderAccessing
    /// The shelf's grants. A separate seam from `folderAccess` — see
    /// `FolderSetAccessing`, which exists precisely so the two cannot be
    /// confused for one another.
    let shelfAccess: FolderSetAccessing

    /// Coalesces a burst of arriving files into a single notification.
    var notificationTask: Task<Void, Never>?
    /// Decides whether a settled pile is worth speaking up about.
    var announcer = WaitingAnnouncer()

    init(
        watcher: FileWatching = MacPlatform.makeFileWatcher(),
        classifier: RuleBasedClassifier = RuleBasedClassifier(),
        organizer: Organizer = Organizer(),
        history: OperationHistory = OperationHistory(),
        // Defaults are built inside rather than in the parameter list:
        // making a notifier is main-actor work, and a default argument is
        // evaluated before the initializer's isolation applies.
        notifier: Notifying? = nil,
        folderAccess: FolderAccessing? = nil,
        shelfAccess: FolderSetAccessing? = nil
    ) {
        self.watcher = watcher
        self.classifier = classifier
        self.organizer = organizer
        self.history = history
        self.notifier = notifier ?? MacPlatform.makeNotifier()
        self.folderAccess = folderAccess ?? MacPlatform.makeFolderAccess()
        self.shelfAccess = shelfAccess ?? MacPlatform.makeShelfFolderAccess()
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
    }

    /// Picks up where the last launch left off.
    ///
    /// Deliberately not part of `init`: restoring a grant opens a
    /// security-scoped resource and starts a file-system watcher on the
    /// user's own folder, and nobody should get that merely by constructing
    /// one of these. The app calls it once, when the menu bar item appears.
    func start() {
        Task { await refreshProviderStatus() }

        // Resume the folder granted on a previous launch. Under the sandbox
        // this is the only way back in without asking the user again.
        if let remembered = folderAccess.restore() {
            beginWatching(remembered, alreadyAuthorized: true)
        }

        // The shelf's own grants, restored the same way and for the same
        // reason. Kept out of `init` on the same principle: this opens
        // operating-system resources, one per folder.
        restoreShelf()
    }

    /// What is waiting, as the plan sees it (e.g. "Thesis  4").
    ///
    /// Read from the plan, not from the classifier, because the plan is what
    /// will actually happen — see `OrganizationPlan.waiting`, which the
    /// verification suite drives. The review window and the notch HUD both
    /// count the plan; this is the surface that used to disagree with them.
    var summaryByCategory: [OrganizationPlan.WaitingEntry] {
        if let plan { return plan.waiting }

        // No plan yet. Nothing better can be said than what the filename
        // rules already know, which is exactly what this said before.
        var counts: [String: Int] = [:]
        var order: [String] = []
        for file in detectedFiles {
            let label: String
            switch sortingMode {
            case .byType:
                // No waiting, and no "Sorting…": the answer is already known
                // from the filename, so the summary can be right immediately.
                label = TypeSorter.folder(for: file) ?? OrganizationPlan.leftAloneLabel
            case .byMeaning:
                label = classifications[file.id]?.project
                    ?? classifications[file.id]?.category
                    ?? "Sorting…"
            }
            if counts[label] == nil { order.append(label) }
            counts[label, default: 0] += 1
        }
        return order.map { OrganizationPlan.WaitingEntry(label: $0, count: counts[$0] ?? 0) }
    }

    /// How many files the Review button offers to show: the moves the plan
    /// proposes, which is what the review window's own header counts.
    var reviewableCount: Int {
        plan?.allMoves.count ?? detectedFiles.count
    }

    var canUndo: Bool { history.mostRecentUndoable != nil }

    // MARK: - Watching

    // MARK: - Review

    // MARK: - Organizing

}
