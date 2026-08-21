import SwiftUI
import HootKit

/// Every move Hoot has made, newest first, each batch reversible.
struct HistoryView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: HootMark.headerIcon)
                Text("History").font(.headline)
                Spacer()
                if !appState.batches.isEmpty {
                    Button("Clear") { appState.clearHistory() }
                        .controlSize(.small)
                        .help("Forget these records. Files already moved stay where they are.")
                }
            }
            .padding(14)

            Divider()

            if appState.batches.isEmpty {
                VStack(spacing: 8) {
                    Text("No files organized yet.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(appState.batches) { batch in
                            BatchSection(batch: batch, appState: appState)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct BatchSection: View {
    let batch: OperationBatch
    @ObservedObject var appState: AppState

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(Self.timeFormatter.string(from: batch.performedAt))
                    .font(.callout.weight(.semibold))

                if batch.isUndone {
                    Text("Undone")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !batch.isUndone {
                    Button("Undo") {
                        appState.undo(batch)
                    }
                    .controlSize(.small)
                }
            }

            ForEach(batch.operations) { operation in
                VStack(alignment: .leading, spacing: 1) {
                    Text(operation.filename)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("→ \(operation.destination.deletingLastPathComponent().path)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .opacity(batch.isUndone ? 0.5 : 1)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
