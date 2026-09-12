import SwiftUI
import HootKit

/// One detected file: icon, name, basic metadata, and where it is headed.
struct FileRow: View {
    let file: FileItem
    let classification: ClassificationResult?
    /// The mode decides which answer is the true one for this row. Showing a
    /// meaning badge while the plan files by type would have the popover and
    /// the review window disagreeing about the same file.
    var mode: SortingMode = .byMeaning

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: file.kind.symbolName)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(metadataLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if mode == .byType {
                TypeBadge(folder: TypeSorter.folder(for: file))
            } else if let classification {
                ClassificationBadge(classification: classification)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var metadataLine: String {
        let sizePart = file.displaySize
        if let modified = file.modifiedAt {
            return "\(sizePart) · \(Self.relativeFormatter.localizedString(for: modified, relativeTo: .now))"
        }
        return sizePart
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

private struct ClassificationBadge: View {
    let classification: ClassificationResult

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(classification.project ?? classification.category)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Text(confidenceLabel)
                .font(.caption2)
                .foregroundStyle(confidenceColor)
        }
    }

    private var confidenceLabel: String {
        "\(Int(classification.confidence * 100))% confident"
    }

    private var confidenceColor: Color {
        if classification.isLowConfidence { return .secondary }
        if classification.confidence >= 0.8 { return .green }
        return .orange
    }
}

/// Where a file goes when Hoot is sorting by type.
///
/// No percentage: the extension either identifies the file or it doesn't, and
/// a confidence score on a fact reads as hedging about something that isn't
/// in doubt.
private struct TypeBadge: View {
    let folder: String?

    var body: some View {
        Text(folder ?? "Left alone")
            .font(.caption.weight(.medium))
            .foregroundStyle(folder == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .lineLimit(1)
    }
}
