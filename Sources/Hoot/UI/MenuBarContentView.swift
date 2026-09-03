import SwiftUI
import AppKit
import HootKit

/// The popover content shown when the menu bar mark is clicked.
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
                if !appState.summaryByCategory.isEmpty {
                    summaryRow
                    Divider()
                }
                fileList
                Divider()
                reviewBar
            }

            if !appState.issues.isEmpty {
                Divider()
                issueList
            }

            Divider()
            footer
        }
        .frame(width: 360)
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

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: HootMark.headerIcon)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Hoot")
                    .font(.headline)
                Text(appState.watchedFolder?.path ?? "No folder selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer()
        }
        .padding(12)
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

    private var summaryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(appState.summaryByCategory, id: \.label) { entry in
                    CategoryChip(label: entry.label, count: entry.count)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var fileList: some View {
        Group {
            if appState.detectedFiles.isEmpty {
                Text(appState.isScanning ? "Scanning…" : "No files yet. New files will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(20)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.detectedFiles) { file in
                            FileRow(file: file, classification: appState.classifications[file.id])
                            if file.id != appState.detectedFiles.last?.id {
                                Divider().padding(.leading, 40)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
    }

    /// The primary call to action: build a proposal and open the review
    /// window. Files are never moved from here directly.
    private var reviewBar: some View {
        VStack(spacing: 6) {
            if let message = appState.lastMessage {
                HStack(spacing: 6) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
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
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("r", modifiers: .command)
            // Not disabled while analyzing: the window opens immediately and
            // shows progress there, and a click mid-analysis simply joins the
            // run already under way.
            .disabled(appState.detectedFiles.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Button(appState.watchedFolder == nil ? "Choose Folder…" : "Change Folder…") {
                appState.presentFolderPicker()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)

            Spacer()

            Button("History") {
                openWindow(id: WindowID.history)
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .keyboardShortcut("y", modifiers: .command)

            Button("Settings") {
                openWindow(id: WindowID.settings)
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .keyboardShortcut(",", modifiers: .command)

            Button("Quit Hoot") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .font(.callout)
    }
}

private struct CategoryChip: View {
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption.weight(.medium))
            Text("\(count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}
