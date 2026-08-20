import Foundation
import AppKit

/// The app's single source of truth: which folder is being watched, what's
/// been discovered in it, the classification for each file, and the history of
/// moves already made. UI reads from here; it never touches the watcher,
/// analyzer, classifier, or organizer directly.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var watchedFolder: URL?
    @Published private(set) var detectedFiles: [FileItem] = []
    @Published private(set) var classifications: [UUID: ClassificationResult] = [:]
    @Published private(set) var isScanning = false

    /// The current proposal awaiting review. Nothing has moved while this is set.
    @Published var plan: OrganizationPlan?
    @Published private(set) var batches: [OperationBatch] = []
    @Published var lastMessage: String?
    /// Problems worth telling the user about. Kept short: the most recent
    /// few, newest first.
    @Published private(set) var issues: [UserFacingIssue] = []

    /// True while a model is working out how files group together.
    @Published private(set) var isAnalyzing = false

    /// Identifies the file set and preferences the current plan was built
    /// from, so an unchanged folder never pays for analysis twice.
    private var planSignature: String?
    /// The single in-flight analysis, shared by the background pass and any
    /// user request that arrives while it's running.
    private var analysisTask: Task<Void, Never>?
    /// Category refinements keyed by file signature, so adding one file
    /// doesn't re-analyze the ones already understood.
    private var refinementCache: [String: ClassificationResult] = [:]
    @Published var settings: AISettings {
        didSet { settings.save() }
    }
    /// Folder names the user has corrected before.
    @Published private(set) var folderPreferences: FolderPreferences
    /// What Hoot has learned from folders the user organized themselves.
    @Published private(set) var learned: LearnedClassifier?
    /// Leave-one-out accuracy of `learned`, shown so its worth is visible.
    @Published private(set) var learnedAccuracy: Double?
    /// Times the user overruled Hoot, fed back into the personal model.
    @Published private(set) var corrections = CorrectionLog.load()
    /// Text read from inside each file, so the review screen can show *why*
    /// a suggestion was made rather than asking for blind trust.
    @Published private(set) var evidence: [UUID: String] = [:]
    /// What the AI layer is currently able to do, for display in Settings.
    @Published private(set) var providerStatus: String = "Checking…"

    /// True until the user has been through the first-run screen.
    @Published private(set) var needsOnboarding: Bool

    private static let onboardingKey = "onboarding.completed"

    private let watcher: FileWatching
    private let classifier: FileClassifier
    private let planner = OrganizationPlanner()
    private let organizer: Organizer
    private let history: OperationHistory
    private let notifications = NotificationService()
    private let folderAccess = WatchedFolderAccess()

    /// Coalesces a burst of arriving files into a single notification.
    private var notificationTask: Task<Void, Never>?
    /// How many files had already been announced, so we only speak up when
    /// the pile actually grows.
    private var lastNotifiedCount = 0

    init(
        watcher: FileWatching = FileWatcher(),
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

    /// Reports whether the configured provider can actually run, so Settings
    /// can say "on-device model still downloading" instead of failing silently.
    func refreshProviderStatus() async {
        guard let provider = ProviderFactory.makeProvider(for: settings) else {
            providerStatus = "Using filename rules only."
            return
        }
        switch await provider.availability() {
        case .available:
            providerStatus = "\(provider.displayName) is ready."
        case .unavailable(let reason):
            providerStatus = "\(reason) Falling back to filename rules."
            report(
                UserFacingIssue(
                    title: "Smart sorting is off.",
                    suggestion: "\(reason) Hoot will sort by filename instead.",
                    severity: .warning
                )
            )
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

    /// Records a problem for display, and logs it for diagnosis.
    private func report(_ issue: UserFacingIssue, underlying: Error? = nil) {
        NSLog("Hoot: \(issue.title)\(underlying.map { " — \($0.localizedDescription)" } ?? "")")
        issues.removeAll { $0.title == issue.title }
        issues.insert(issue, at: 0)
        if issues.count > 5 { issues = Array(issues.prefix(5)) }
    }

    func dismissIssue(_ id: UUID) {
        issues.removeAll { $0.id == id }
    }

    func dismissAllIssues() {
        issues.removeAll()
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingKey)
        needsOnboarding = false
    }

    // MARK: - Watching

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

        ProviderFactory.makeProvider(for: settings)?.prewarm()
        precomputePlan()
    }

    private func scanExistingFiles(in folder: URL) {
        isScanning = true
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in contents where !FileAnalyzer.isIgnored(url) {
            ingest(url: url)
        }
        isScanning = false
    }

    private func ingest(url: URL) {
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

    /// Waits for the folder to settle before announcing anything — unzipping
    /// an archive can produce dozens of files in a second, and each one
    /// shouldn't be its own notification.
    private func scheduleWaitingNotification() {
        guard !isScanning else { return } // the initial sweep isn't news
        notificationTask?.cancel()
        notificationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self else { return }
            await self.notifyIfPileGrew()
        }
    }

    private func notifyIfPileGrew() async {
        // The folder has stopped changing: a good moment to do the expensive
        // analysis, so it's finished before Review is ever clicked.
        ProviderFactory.makeProvider(for: settings)?.prewarm()
        precomputePlan()

        let count = detectedFiles.count
        guard count > lastNotifiedCount else { return }
        lastNotifiedCount = count
        await notifications.notifyFilesWaiting(
            count: count,
            topGroup: summaryByCategory.first?.label
        )
    }

    // MARK: - Review

    /// Builds a proposal from what's currently known. Purely in-memory —
    /// files are never moved until the user approves.
    ///
    /// Project detection runs here rather than during discovery: a model pass
    /// takes seconds, and it needs to see the whole set at once to spot which
    /// files belong together.
    /// Ensures a current plan exists, reusing one already computed.
    ///
    /// Analysis is expensive (seconds of on-device inference), so it is done
    /// once per unique file set and shared: a background pass usually starts
    /// as soon as files settle, and pressing Review then either returns
    /// immediately or joins the run already in progress.
    func buildPlan(force: Bool = false) async {
        guard watchedFolder != nil else { return }

        if force {
            analysisTask?.cancel()
            analysisTask = nil
            planSignature = nil
        }

        // Join an in-flight run rather than starting a competing one.
        if let running = analysisTask {
            await running.value
            return
        }

        let signature = currentSignature()
        if !force, planSignature == signature, plan != nil { return }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performAnalysis(signature: signature)
        }
        analysisTask = task
        await task.value
        analysisTask = nil
    }

    /// Starts analysis without waiting for it, so results are ready before
    /// the user asks. Cheap when the plan is already current.
    func precomputePlan() {
        guard watchedFolder != nil, !detectedFiles.isEmpty else { return }
        guard planSignature != currentSignature() || plan == nil else { return }
        Task { await buildPlan() }
    }

    private func currentSignature() -> String {
        let files = detectedFiles.map(\.signature).sorted().joined(separator: ";")
        let prefs = folderPreferences.entries
            .map { "\($0.proposed)>\($0.preferred)" }
            .joined(separator: ",")
        return "\(files)#\(prefs)#\(settings.provider.rawValue)"
    }

    private func performAnalysis(signature: String) async {
        guard let root = watchedFolder else { return }

        isAnalyzing = true
        defer { isAnalyzing = false }

        let detector = makeDetector()
        let files = detectedFiles
        let (projects, ungrouped) = await detector.detectProjects(in: files)
        guard !Task.isCancelled else { return }

        // Gather what was read from inside each file, for the review screen.
        if settings.allowLocalContentReading {
            let extractor = TextExtractor()
            var gathered: [UUID: String] = [:]
            for file in files {
                if let excerpt = extractor.evidence(for: file)?.excerpt {
                    gathered[file.id] = excerpt
                }
            }
            evidence = gathered
        }

        // Publish the grouping straight away. Refinement below only adjusts
        // folders for loose files, so there's no reason to make the user
        // stare at a spinner while it runs.
        plan = planner.makePlan(
            root: root,
            detectedProjects: projects,
            ungrouped: ungrouped,
            classifications: classifications,
            preferences: folderPreferences
        )

        var effective = classifications

        // The user's own filing habits outrank any general guess, and cost
        // nothing to consult — so anything the personal model recognizes is
        // settled here, and never sent to the language model at all.
        var stillUnknown = ungrouped
        if let learned, learned.isUsable {
            var settled: [UUID] = []
            for file in ungrouped {
                guard let prediction = learned.predict(TrainingCorpus.features(for: file)),
                      let folder = SuggestionValidator.sanitizeUserFolderName(prediction.folder)
                else { continue }

                effective[file.id] = ClassificationResult(
                    fileID: file.id,
                    category: folder,
                    project: nil,
                    suggestedFolder: folder,
                    suggestedName: classifications[file.id]?.suggestedName ?? file.filename,
                    confidence: ConfidenceModel.combine([.matchesUserHistory]),
                    reason: "You usually file files like this under “\(folder)”."
                )
                settled.append(file.id)
            }
            let settledSet = Set(settled)
            stillUnknown = ungrouped.filter { !settledSet.contains($0.id) }
        }

        if let provider = ProviderFactory.makeProvider(for: settings), !stillUnknown.isEmpty {
            let folders = ExistingFolders(in: root).allNames
            let cacheSalt = folders.sorted().joined(separator: ",")

            // Reuse refinements already computed for unchanged files.
            var pending: [FileItem] = []
            for file in stillUnknown {
                if let cached = refinementCache["\(file.signature)#\(cacheSalt)"] {
                    effective[file.id] = ClassificationResult(
                        fileID: file.id,
                        category: cached.category,
                        project: cached.project,
                        suggestedFolder: cached.suggestedFolder,
                        suggestedName: cached.suggestedName,
                        confidence: cached.confidence,
                        reason: cached.reason
                    )
                } else {
                    pending.append(file)
                }
            }

            if !pending.isEmpty {
                let refiner = CategoryRefiner(
                    provider: provider,
                    allowContentReading: settings.allowLocalContentReading
                )
                let refined = await refiner.refine(
                    pending,
                    existing: effective,
                    preferredFolders: folders
                )
                guard !Task.isCancelled else { return }

                for file in pending {
                    guard let result = refined[file.id] else { continue }
                    refinementCache["\(file.signature)#\(cacheSalt)"] = result
                }
                effective.merge(refined) { _, new in new }
            }
        }

        guard !Task.isCancelled else { return }
        plan = planner.makePlan(
            root: root,
            detectedProjects: projects,
            ungrouped: ungrouped,
            classifications: effective,
            preferences: folderPreferences
        )
        planSignature = signature
    }

    /// Uses the configured provider when one is available, and plain rules
    /// otherwise. The AI detector falls back to rules internally too, so a
    /// provider failure mid-request still produces a usable plan.
    private func makeDetector() -> ProjectDetecting {
        guard let provider = ProviderFactory.makeProvider(for: settings) else {
            return RuleBasedProjectDetector()
        }
        return AIProjectDetector(
            provider: provider,
            allowContentReading: settings.allowLocalContentReading
        )
    }

    func setApproval(_ approved: Bool, forMove moveID: UUID) {
        guard var current = plan else { return }
        for groupIndex in current.groups.indices {
            guard let moveIndex = current.groups[groupIndex].moves.firstIndex(where: { $0.id == moveID })
            else { continue }
            current.groups[groupIndex].moves[moveIndex].isApproved = approved
            plan = current
            return
        }
    }

    /// Renames a group's destination folder, and remembers the correction so
    /// the same suggestion arrives already renamed next time.
    ///
    /// The typed name is sanitized as a path component but otherwise left
    /// alone — unlike model output, the user is allowed to call a folder
    /// whatever they like.
    func renameGroup(_ groupID: UUID, to newName: String) {
        guard var current = plan,
              let groupIndex = current.groups.firstIndex(where: { $0.id == groupID }),
              let safeName = SuggestionValidator.sanitizeUserFolderName(newName)
        else { return }

        let group = current.groups[groupIndex]
        guard safeName != group.name else { return }

        current.groups[groupIndex].name = safeName
        for moveIndex in current.groups[groupIndex].moves.indices {
            current.groups[groupIndex].moves[moveIndex].destinationFolder = safeName
        }
        plan = current

        folderPreferences.remember(proposed: group.proposedName, preferred: safeName)
        folderPreferences.save()
    }

    func forgetFolderPreference(proposed: String) {
        folderPreferences.forget(proposed: proposed)
        folderPreferences.save()
    }

    /// Rebuilds the personal model from the watched folder's own subfolders.
    ///
    /// Nothing is asked of the user: a file already sitting in "Finance" is a
    /// labelled example of what they mean by finance. Reports measured
    /// accuracy rather than assuming the model is worth using.
    func relearnFromFolders() async {
        guard let root = watchedFolder else { return }

        // Folders show where files ended up; corrections show where Hoot was
        // wrong. Both are training data, the latter weighted more heavily.
        let samples = TrainingCorpus.gather(from: root) + corrections.trainingSamples
        guard samples.count >= LearnedClassifier.minimumCorpusSize else {
            learned = nil
            learnedAccuracy = nil
            lastMessage = "Not enough sorted files yet — Hoot needs about "
                + "\(LearnedClassifier.minimumCorpusSize) across a few folders."
            return
        }

        let model = LearnedClassifier.train(on: samples)
        let (accuracy, answered, total) = LearnedClassifier.crossValidate(samples)

        model.save()
        learned = model.isUsable ? model : nil
        learnedAccuracy = answered > 0 ? accuracy : nil
        lastMessage = "Learned from \(total) files — right \(Int(accuracy * 100))% of the time "
            + "on the \(Int(Double(answered) / Double(total) * 100))% it recognizes."
    }

    func forgetLearnedFolders() {
        learned = nil
        learnedAccuracy = nil
        LearnedClassifier().save()
        lastMessage = "Forgot what Hoot learned from your folders."
    }

    func clearFolderPreferences() {
        folderPreferences.removeAll()
        folderPreferences.save()
        lastMessage = "Forgot your saved folder names."
    }

    /// Moves one file into a different group, because the user said so.
    ///
    /// This is the correction that teaches: the choice is recorded and fed
    /// back into the personal model, so files described the same way go to
    /// the right place next time without being asked again.
    func moveFile(_ moveID: UUID, toGroup targetGroupID: UUID) {
        guard var current = plan,
              let targetIndex = current.groups.firstIndex(where: { $0.id == targetGroupID })
        else { return }

        // Find and detach the move from wherever it currently sits.
        var moved: PlannedMove?
        for groupIndex in current.groups.indices {
            guard let moveIndex = current.groups[groupIndex].moves
                .firstIndex(where: { $0.id == moveID }) else { continue }
            guard groupIndex != targetIndex else { return }   // already there
            moved = current.groups[groupIndex].moves.remove(at: moveIndex)
            break
        }
        guard var move = moved else { return }

        let destination = current.groups[targetIndex].name
        let rejected = move.destinationFolder

        move.destinationFolder = destination
        // A role subfolder described the old grouping and rarely survives the
        // move; superseded versions keep theirs, since that is about age.
        if move.roleSubfolder != OrganizationPlanner.demotedSubfolder {
            move.roleSubfolder = nil
        }
        move.isApproved = true
        current.groups[targetIndex].moves.append(move)
        current.groups[targetIndex].moves.sort { $0.file.filename < $1.file.filename }

        // Groups emptied by the move stop being proposed.
        current.groups.removeAll { $0.moves.isEmpty }
        plan = current

        corrections.record(
            features: TrainingCorpus.features(for: move.file),
            chose: destination,
            insteadOf: rejected
        )
        corrections.save()
        lastMessage = "Moved to “\(destination)”. Hoot will remember."
    }

    func clearCorrections() {
        corrections.removeAll()
        corrections.save()
        lastMessage = "Forgot your past corrections."
    }

    /// Bulk toggle for the review window's All / None buttons.
    func setApprovalForAll(_ approved: Bool) {
        guard var current = plan else { return }
        for groupIndex in current.groups.indices {
            for moveIndex in current.groups[groupIndex].moves.indices {
                current.groups[groupIndex].moves[moveIndex].isApproved = approved
            }
        }
        plan = current
    }

    func setApproval(_ approved: Bool, forGroup groupID: UUID) {
        guard var current = plan else { return }
        guard let groupIndex = current.groups.firstIndex(where: { $0.id == groupID }) else { return }
        for moveIndex in current.groups[groupIndex].moves.indices {
            current.groups[groupIndex].moves[moveIndex].isApproved = approved
        }
        plan = current
    }

    // MARK: - Organizing

    /// Executes the approved moves in the current plan.
    func organizeApproved() {
        guard let current = plan else { return }
        let approved = current.approvedMoves
        guard !approved.isEmpty else { return }

        let (batch, failures) = organizer.organize(current)

        if !batch.operations.isEmpty {
            history.record(batch)
            batches = history.batches

            // Files that moved out of the watched folder are no longer pending.
            let movedURLs = Set(batch.operations.map(\.source))
            detectedFiles.removeAll { movedURLs.contains($0.url) }
        }

        lastMessage = Self.summary(moved: batch.operations.count, failures: failures.count)
        lastNotifiedCount = detectedFiles.count
        notifications.clearPending()
        for (move, error) in failures {
            report(
                UserFacingIssue(
                    title: "Couldn't move “\(move.file.filename)”.",
                    suggestion: (error as? OrganizerError).map { organizerAdvice(for: $0) }
                        ?? error.localizedDescription
                ),
                underlying: error
            )
        }

        plan = nil
        planSignature = nil
    }

    func undo(_ batch: OperationBatch) {
        let (restored, failures) = organizer.undo(batch)

        if !restored.isEmpty {
            history.markUndone(batch.id)
            batches = history.batches
            // Restored files are back in the watched folder — pick them up again.
            for operation in restored where operation.source.deletingLastPathComponent() == watchedFolder {
                ingest(url: operation.source)
            }
        }

        if failures.isEmpty {
            lastMessage = "Put \(restored.count) \(restored.count == 1 ? "file" : "files") back."
        } else {
            lastMessage = "Restored \(restored.count); \(failures.count) couldn't be undone."
            for (operation, error) in failures {
                report(
                    UserFacingIssue(
                        title: "Couldn't put “\(operation.filename)” back.",
                        suggestion: (error as? OrganizerError).map { organizerAdvice(for: $0) }
                            ?? error.localizedDescription
                    ),
                    underlying: error
                )
            }
        }
    }

    /// Discards the operation log. Entries can go stale when files are moved
    /// outside Hoot, at which point undo can no longer find them.
    func clearHistory() {
        history.clear()
        batches = history.batches
        lastMessage = "History cleared."
    }

    func undoLast() {
        guard let batch = history.mostRecentUndoable else { return }
        undo(batch)
    }

    /// Turns an organizer error into something actionable.
    private func organizerAdvice(for error: OrganizerError) -> String {
        switch error {
        case .sourceMissing:
            return "It was moved or deleted while Hoot was working."
        case .destinationOccupied(let url):
            return "Something else is already at \(url.lastPathComponent)."
        case .escapesWatchedFolder:
            return "That folder is a shortcut leading outside the watched folder, "
                + "so Hoot won't move files into it."
        }
    }

    private static func summary(moved: Int, failures: Int) -> String {
        let movedPart = "Organized \(moved) \(moved == 1 ? "file" : "files")."
        return failures == 0 ? movedPart : "\(movedPart) \(failures) couldn't be moved."
    }
}
