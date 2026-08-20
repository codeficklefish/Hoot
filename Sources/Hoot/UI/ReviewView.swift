import SwiftUI

/// The approval gate. Hoot never moves anything until the user has seen this
/// screen and chosen to organize — and each file can be individually excluded.
struct ReviewView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if appState.isAnalyzing, appState.plan == nil {
                analyzingState
            } else if let plan = appState.plan, !plan.isEmpty {
                header(plan: plan)
                Divider()
                content(plan: plan)
                Divider()
                footer(plan: plan)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private func header(plan: OrganizationPlan) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: HootMark.headerIcon)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hoot found \(plan.allMoves.count) \(plan.allMoves.count == 1 ? "file" : "files")")
                    .font(.headline)
                Text(plan.root.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
            if appState.isAnalyzing {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("Refining…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
    }

    private func content(plan: OrganizationPlan) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(plan.groups) { group in
                    GroupSection(group: group, appState: appState)
                }

                if !plan.skipped.isEmpty {
                    SkippedSection(skipped: plan.skipped)
                }
            }
            .padding(14)
        }
    }

    private func footer(plan: OrganizationPlan) -> some View {
        HStack {
            Text("\(plan.approvedMoves.count) selected")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("All") { appState.setApprovalForAll(true) }
                .controlSize(.small)
                .keyboardShortcut("a", modifiers: .command)
                .help("Select every suggested move (⌘A)")

            Button("None") { appState.setApprovalForAll(false) }
                .controlSize(.small)
                .keyboardShortcut("d", modifiers: .command)
                .help("Deselect everything (⌘D)")

            Spacer()

            Button("Cancel") {
                appState.plan = nil
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Organize") {
                appState.organizeApproved()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(plan.approvedMoves.isEmpty)
        }
        .padding(14)
    }

    private var analyzingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Working out what belongs together…")
                .foregroundStyle(.secondary)
            Text(appState.settings.provider == .rulesOnly
                 ? "Matching filenames."
                 : "Running on-device — nothing leaves this Mac.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(nsImage: HootMark.headerIcon)
                .opacity(0.5)
            Text("Nothing to organize right now.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One proposed destination folder and the files headed into it.
private struct GroupSection: View {
    let group: PlannedGroup
    @ObservedObject var appState: AppState

    /// Local copy so typing doesn't rebuild the plan on every keystroke;
    /// the rename is committed on Return or when focus leaves.
    @State private var draftName: String = ""
    @FocusState private var isEditingName: Bool
    /// Highlights the folder a dragged file would land in.
    @State private var isTargeted = false

    private var allApproved: Bool {
        group.moves.allSatisfy(\.isApproved)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Toggle(isOn: Binding(
                    get: { allApproved },
                    set: { appState.setApproval($0, forGroup: group.id) }
                )) {
                    Image(systemName: "folder")
                }
                .toggleStyle(.checkbox)
                .labelsHidden()

                TextField("Folder name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.semibold))
                    .focused($isEditingName)
                    .onSubmit { commitRename() }
                    .onChange(of: isEditingName) { editing in
                        if !editing { commitRename() }
                    }
                    .help("Rename this folder. Hoot will remember your choice.")

                Spacer()

                Text("\(group.approvedCount)/\(group.moves.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .onAppear { draftName = group.name }
            .onChange(of: group.name) { newValue in
                // Keep the field in step when the plan is rebuilt.
                if !isEditingName { draftName = newValue }
            }

            Text(group.rationale)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 20)

            if group.name.lowercased() != group.proposedName.lowercased() {
                Label("Renamed from “\(group.proposedName)” — Hoot will remember.",
                      systemImage: "pencil")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 20)
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(group.moves) { move in
                    MoveRow(move: move, appState: appState)
                }
            }
            .padding(.leading, 20)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(isTargeted ? 0.16 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor, lineWidth: isTargeted ? 2 : 0)
        )
        // Dropping a file here says "this one belongs in this folder", which
        // both fixes the plan and teaches Hoot for next time.
        .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                guard let raw = value as? String, let moveID = UUID(uuidString: raw) else { return }
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.18)) {
                        appState.moveFile(moveID, toGroup: group.id)
                    }
                }
            }
            return true
        }
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != group.name else {
            draftName = group.name // reject empties by snapping back
            return
        }
        appState.renameGroup(group.id, to: trimmed)
    }
}

private struct MoveRow: View {
    let move: PlannedMove
    @ObservedObject var appState: AppState

    /// Evidence is hidden until asked for: most of the time the destination is
    /// all anyone wants, but when a suggestion looks wrong the reasoning is
    /// the difference between correcting it and distrusting the whole app.
    @State private var isShowingEvidence = false

    private var isDemoted: Bool {
        move.roleSubfolder == OrganizationPlanner.demotedSubfolder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle(isOn: Binding(
                    get: { move.isApproved },
                    set: { appState.setApproval($0, forMove: move.id) }
                )) {
                    HStack(spacing: 6) {
                        Image(systemName: move.file.kind.symbolName)
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(move.file.filename)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .toggleStyle(.checkbox)

                Spacer(minLength: 8)

                if isDemoted {
                    Label("older version", systemImage: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .help("A newer version exists. Hoot keeps this one — it just moves it out of the way rather than deleting it.")
                }

                ConfidenceDot(confidence: move.classification.confidence)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { isShowingEvidence.toggle() }
                } label: {
                    Image(systemName: isShowingEvidence ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Why here?")
            }

            if isShowingEvidence {
                EvidencePanel(move: move, excerpt: appState.evidence[move.file.id])
                    .padding(.leading, 22)
            }
        }
        .font(.callout)
        .opacity(isDemoted ? 0.55 : 1)
        .contentShape(Rectangle())
        // Dragging a file to another folder is the natural way to say "not
        // there, here" — and it is the correction Hoot learns from.
        .onDrag {
            NSItemProvider(object: move.id.uuidString as NSString)
        }
    }
}

/// Confidence at a glance, with the reasoning behind it on hover.
private struct ConfidenceDot: View {
    let confidence: Double

    private var color: Color {
        if confidence >= 0.8 { return .green }
        if confidence >= 0.6 { return .yellow }
        return .orange
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .help("\(Int(confidence * 100))% confident")
    }
}

/// What the suggestion actually rests on.
private struct EvidencePanel: View {
    let move: PlannedMove
    let excerpt: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(move.classification.reason, systemImage: "lightbulb")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let excerpt, !excerpt.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Read from inside the file")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(excerpt.prefix(220) + (excerpt.count > 220 ? "…" : ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(move.destinationSubpath + "/" + move.destinationName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("Drag this file onto another folder to correct it.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Files Hoot chose not to touch. Shown so the decision is visible rather
/// than silent, but they carry no checkbox — low confidence means hands off.
private struct SkippedSection: View {
    let skipped: [(file: FileItem, reason: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "hand.raised")
                Text("Left alone (\(skipped.count))").fontWeight(.semibold)
            }
            Text("Hoot wasn't confident enough to suggest a folder for these.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(skipped, id: \.file.id) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.file.kind.symbolName)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(item.file.filename)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .help(item.reason)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
