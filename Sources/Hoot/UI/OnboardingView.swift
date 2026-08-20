import SwiftUI

/// Shown once, on first launch. Three things the user needs to know before
/// handing an app permission to move their files: what it does, that it asks
/// first, and where their data goes.
struct OnboardingView: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: HootMark.onboardingIcon)
                Text("Hoot")
                    .font(.system(size: 26, weight: .semibold))
                Text("Tidies your Downloads by working out what belongs together.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 32)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 16) {
                Point(
                    symbol: "rectangle.stack",
                    title: "Groups by project, not file type",
                    detail: "A boarding pass, a hotel booking and an itinerary become one trip folder."
                )
                Point(
                    symbol: "checkmark.shield",
                    title: "Never moves anything on its own",
                    detail: "You see every suggestion first, and any move can be undone later."
                )
                Point(
                    symbol: "lock",
                    title: "Stays on this Mac",
                    detail: "Analysis runs on-device. Nothing is uploaded and there's no account."
                )
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 24)

            VStack(spacing: 8) {
                Button {
                    // The picker is asynchronous now, so completion is driven
                    // by the folder actually being chosen (below) rather than
                    // assumed the moment the panel opens.
                    appState.presentFolderPicker()
                } label: {
                    Text("Choose a Folder to Watch…")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Button("Later") {
                    appState.completeOnboarding()
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
        }
        .frame(width: 460, height: 560)
        // Single-parameter form: the two-parameter onChange needs macOS 14,
        // and Hoot still supports 13.
        .onChange(of: appState.watchedFolder) { folder in
            guard folder != nil else { return }
            appState.completeOnboarding()
            dismiss()
        }
    }
}

private struct Point: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
