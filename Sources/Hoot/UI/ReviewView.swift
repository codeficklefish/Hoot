import SwiftUI
import HootKit

/// The approval gate. Hoot never moves anything until the user has seen this
/// screen and chosen to organize — and each file can be individually excluded.
struct ReviewView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// One Quick Look panel for the whole screen, driven by whichever row was
    /// held. Setting it opens the panel; the panel clears it when dismissed.
    @State private var previewURL: URL?

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
        // Quick Look is what the Finder shows for the same gesture, so a file
        // opens the way people already expect. Cleared straight after, so
        // holding the same row twice opens it again rather than doing nothing.
        .onChange(of: previewURL) { url in
            guard let url else { return }
            QuickLookPanel.shared.show(url)
            previewURL = nil
        }
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
                    GroupSection(group: group, appState: appState, previewURL: $previewURL)
                        .scrollReveal()
                        // A group emptied by a drag should leave, not vanish.
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.97)),
                            removal: .opacity.combined(with: .scale(scale: 0.94))
                        ))
                }

                if !plan.skipped.isEmpty {
                    SkippedSection(skipped: plan.skipped, previewURL: $previewURL)
                        .scrollReveal()
                }
            }
            .padding(14)
            .animation(Motion.move, value: plan.groups.map(\.id))
        }
    }

    private func footer(plan: OrganizationPlan) -> some View {
        HStack {
            Text("\(plan.approvedMoves.count) selected")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .rollingDigits()
                .animation(Motion.state, value: plan.approvedMoves.count)

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
    @Binding var previewURL: URL?

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
                    .rollingDigits()
                    .animation(Motion.state, value: group.approvedCount)
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
                    MoveRow(move: move, appState: appState, previewURL: $previewURL)
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
        // The card lifts slightly under a dragged file, so the drop target is
        // obvious while the pointer is still moving.
        .scaleEffect(isTargeted ? 1.01 : 1)
        .animation(Motion.state, value: isTargeted)
        // Dropping a file here says "this one belongs in this folder", which
        // both fixes the plan and teaches Hoot for next time.
        .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                guard let raw = value as? String, let moveID = UUID(uuidString: raw) else { return }
                Task { @MainActor in
                    withAnimation(Motion.move) {
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

/// Confidence at a glance, with the reasoning behind it on hover.

/// What the suggestion actually rests on.

/// Files Hoot chose not to touch. Shown so the decision is visible rather
/// than silent, but they carry no checkbox — low confidence means hands off.
private struct SkippedSection: View {
    let skipped: [(file: FileItem, reason: String)]
    @Binding var previewURL: URL?

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
                .contentShape(Rectangle())
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .onEnded { _ in previewURL = item.file.url }
                )
                .help("\(item.reason)\n\nHold to preview.")
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
