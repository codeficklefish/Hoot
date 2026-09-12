import SwiftUI
import AppKit
import HootKit

/// The popover shown when the menu bar mark is clicked.
///
/// A summary and a decision, not a file browser. What is waiting is stated as
/// counts per destination; which files those are, and whether each one is
/// right, is the review window's job — a popover that tried to do both would
/// be a worse version of each.
///
/// Every colour here is semantic, so the whole thing follows the system
/// between light and dark without a second palette to keep in step.
struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if appState.watchedFolder == nil {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    sortingSection
                    if !appState.summaryByCategory.isEmpty { waitingSection }
                    actionRow
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            if !appState.issues.isEmpty {
                Divider()
                issueList
            }

            Divider()
            footer
        }
        .frame(width: 340)
        .animation(.easeInOut(duration: 0.18), value: appState.detectedFiles.count)
        .animation(.easeInOut(duration: 0.18), value: appState.lastMessage)
        // Apple Intelligence can be switched on while Hoot is running, and
        // this popover is where the warning about it being off is shown. Ask
        // again each time it opens, so the banner answers to the current
        // state of the machine rather than the state at launch.
        .task {
            await appState.refreshProviderStatus()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 11) {
            Image(nsImage: HootMark.templateIcon(height: 26))
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Hoot")
                    .font(.title3.weight(.semibold))
                Text(appState.watchedFolder?.path ?? "No folder selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Pick a folder for Hoot to watch, like Downloads or Desktop.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Choose Folder…") {
                appState.presentFolderPicker()
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sorting

    private var sortingSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel("Sorting")

            Picker("", selection: $appState.sortingMode) {
                ForEach(SortingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(appState.sortingMode.tradeoff)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Waiting

    private var waitingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Waiting")
            // Wrapped rather than scrolled sideways: the whole point of this
            // section is to be read at a glance, and a horizontal scroller
            // hides exactly the categories that did not fit.
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(appState.summaryByCategory, id: \.label) { entry in
                    CategoryChip(label: entry.label, count: entry.count)
                }
            }
        }
    }

    // MARK: - Action

    private var actionRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let message = appState.lastMessage {
                HStack(spacing: 6) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if appState.canUndo {
                        Button("Undo") { appState.undoLast() }
                            .controlSize(.small)
                            .keyboardShortcut("z", modifiers: .command)
                    }
                }
                .transition(.opacity)
            }

            Button {
                // Open the window first so the analysis progress is visible,
                // rather than leaving the popover frozen for a few seconds.
                openWindow(id: WindowID.review)
                NSApp.activate(ignoringOtherApps: true)
                Task { await appState.buildPlan() }
            } label: {
                Text("Review \(appState.detectedFiles.count) \(appState.detectedFiles.count == 1 ? "File" : "Files")…")
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: .command)
            // Not disabled while analyzing: the window opens immediately and
            // shows progress there, and a click mid-analysis simply joins the
            // run already under way.
            .disabled(appState.detectedFiles.isEmpty)
        }
    }

    /// Problems Hoot hit, shown where the user will actually see them rather
    /// than only in the console.
    private var issueList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(appState.issues) { issue in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: issue.severity.symbolName)
                        .foregroundStyle(issue.severity == .failure ? .red : .orange)
                        .font(.caption)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(issue.title)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        if let suggestion = issue.suggestion {
                            Text(suggestion)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 4)

                    Button {
                        appState.dismissIssue(issue.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss")
                }
            }

            if appState.issues.count > 1 {
                Button("Dismiss All") { appState.dismissAllIssues() }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            MenuRow(
                symbol: "folder",
                title: appState.watchedFolder == nil ? "Choose Folder…" : "Change Folder…"
            ) {
                appState.presentFolderPicker()
            }

            MenuRow(symbol: "clock.arrow.circlepath", title: "History", shortcut: "⌘Y") {
                openWindow(id: WindowID.history)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("y", modifiers: .command)

            MenuRow(symbol: "gearshape", title: "Settings…", shortcut: "⌘,") {
                openWindow(id: WindowID.settings)
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)

            MenuRow(symbol: "xmark.circle", title: "Quit Hoot", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Pieces

/// The small uppercase heading above each block.
private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.5)
            .foregroundStyle(.secondary)
    }
}

/// One destination and how many files are headed for it.
private struct CategoryChip: View {
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.callout)
            Text("\(count)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
        .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
    }
}

/// One row of the footer menu: icon, label, and the shortcut that also works.
private struct MenuRow: View {
    let symbol: String
    let title: String
    var shortcut: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            // Quaternary rather than a fixed grey: it is defined against the
            // window's own background, so the highlight stays legible in both
            // appearances instead of washing out in one of them.
            .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Lays subviews out left to right, wrapping to a new line when the next one
/// would not fit.
///
/// SwiftUI has no wrapping stack, and the alternatives are both worse here: a
/// horizontal scroller hides the categories that did not fit, and a fixed grid
/// gives a two-letter folder name the same width as a twenty-letter one.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + spacing + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += (x > 0 ? spacing : 0) + size.width
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x)
        }
        return CGSize(width: min(widest, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + spacing + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            if x > bounds.minX { x += spacing }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width
            lineHeight = max(lineHeight, size.height)
        }
    }
}
