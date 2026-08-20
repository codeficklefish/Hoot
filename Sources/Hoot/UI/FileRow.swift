import SwiftUI

/// One detected file: icon, name, basic metadata, and its (mock) classification.
struct FileRow: View {
    let file: FileItem
    let classification: ClassificationResult?

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

            if let classification {
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
