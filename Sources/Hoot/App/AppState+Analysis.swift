import Foundation
import AppKit
import HootKit
import HootPlatformMac

/// Turning what was found into a plan, and keeping that plan current.
///
/// Split out of `AppState` so each part of the app's behaviour can be read
/// on its own; the state itself stays in one place.
extension AppState {

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

    func currentSignature() -> String {
        let files = detectedFiles.map(\.signature).sorted().joined(separator: ";")
        let prefs = folderPreferences.entries
            .map { "\($0.proposed)>\($0.preferred)" }
            .joined(separator: ",")
        return "\(files)#\(prefs)#\(settings.provider.rawValue)#\(sortingMode.rawValue)"
    }

    func performAnalysis(signature: String) async {
        guard let root = watchedFolder else { return }

        // Sorting by type is a loop over filenames, so it returns before the
        // spinner would be worth showing — and never reaches the model, the
        // text extractor or the personal classifier. That is the promise the
        // mode makes, and the cheapest way to keep it is to leave before any
        // of them exist.
        if sortingMode == .byType {
            plan = planner.makeTypePlan(
                root: root,
                files: detectedFiles,
                preferences: folderPreferences
            )
            planSignature = signature
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        let detector = makeDetector()
        let files = detectedFiles
        let (projects, ungrouped) = await detector.detectProjects(in: files)
        guard !Task.isCancelled else { return }

        // Gather what was read from inside each file, for the review screen.
        if settings.allowLocalContentReading {
            let extractor = MacPlatform.makeTextExtractor()
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

        if let provider = MacPlatform.makeAIProvider(for: settings), !stillUnknown.isEmpty {
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
                    extractor: MacPlatform.makeTextExtractor(),
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
    func makeDetector() -> ProjectDetecting {
        guard let provider = MacPlatform.makeAIProvider(for: settings) else {
            return RuleBasedProjectDetector()
        }
        return AIProjectDetector(
            provider: provider,
            extractor: MacPlatform.makeTextExtractor(),
            allowContentReading: settings.allowLocalContentReading
        )
    }
}
