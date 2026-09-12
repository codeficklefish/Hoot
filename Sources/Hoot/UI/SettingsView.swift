import SwiftUI
import HootKit
import HootPlatformMac

/// Where the user chooses how much intelligence Hoot uses, and how much it's
/// allowed to see. The privacy consequence of each choice is stated inline
/// rather than buried in documentation.
struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Section("Sorting") {
                HStack(spacing: 10) {
                    ForEach(SortingMode.allCases) { mode in
                        SortingModeCard(
                            mode: mode,
                            isSelected: appState.sortingMode == mode
                        ) {
                            appState.sortingMode = mode
                        }
                    }
                }
                .padding(.vertical, 2)

                Text(appState.sortingMode.tradeoff)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Intelligence") {
                Picker("Analyze with", selection: $appState.settings.provider) {
                    Text("Filename rules only").tag(AISettings.ProviderKind.rulesOnly)
                    Text("Apple Intelligence (on-device)")
                        .tag(AISettings.ProviderKind.appleOnDevice)
                }
                .pickerStyle(.radioGroup)
                .disabled(!MacPlatform.supportsOnDeviceAI)

                if !MacPlatform.supportsOnDeviceAI {
                    Label("On-device intelligence needs macOS 26 or later.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(appState.providerStatus.contains("ready") ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(appState.providerStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            // Greyed rather than hidden: a person who picked "By type" should
            // still be able to see what the other mode would use, without
            // having to switch to it to find out.
            .disabled(!appState.sortingMode.usesModel)

            Section("Learning from your folders") {
                if let learned = appState.learned, learned.isUsable {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Learned from \(learned.totalSamples) files across \(learned.learnedFolders.count) folders")
                            .font(.callout)
                    }
                    if let accuracy = appState.learnedAccuracy {
                        Text("Correct \(Int(accuracy * 100))% of the time on files it hadn't seen. It stays quiet when unsure rather than guessing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(learned.learnedFolders.prefix(6), id: \.folder) { entry in
                        HStack {
                            Text(entry.folder).font(.callout)
                            Spacer()
                            Text("\(entry.examples) files")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                } else {
                    Text("Hoot can learn how you file things from folders you've already sorted. It needs about \(LearnedClassifier.minimumCorpusSize) files across a few folders, with at least \(LearnedClassifier.minimumExamplesPerFolder) in each.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !appState.corrections.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.draw").foregroundStyle(.secondary)
                        Text("\(appState.corrections.count) correction\(appState.corrections.count == 1 ? "" : "s") from dragging files")
                            .font(.callout)
                        Spacer()
                        Button("Forget") { appState.clearCorrections() }
                            .controlSize(.small)
                    }
                    Text("Corrections count for more than files that merely sit in a folder — being told directly beats being inferred.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button("Learn From My Folders") {
                        Task { await appState.relearnFromFolders() }
                    }
                    .disabled(appState.watchedFolder == nil)

                    if appState.learned != nil {
                        Button("Forget") { appState.forgetLearnedFolders() }
                            .controlSize(.small)
                    }
                }
            }

            Section("Learned folder names") {
                if appState.folderPreferences.isEmpty {
                    Text("Rename a folder in the review window and Hoot will remember it here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(appState.folderPreferences.entries, id: \.proposed) { entry in
                        HStack(spacing: 6) {
                            Text(entry.proposed)
                                .foregroundStyle(.secondary)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(entry.preferred)
                                .fontWeight(.medium)
                            Spacer()
                            Button {
                                appState.forgetFolderPreference(proposed: entry.proposed)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Forget this rename")
                        }
                        .font(.callout)
                    }

                    Button("Forget All") { appState.clearFolderPreferences() }
                        .controlSize(.small)
                }
            }

            Section("Privacy") {
                Toggle("Let the on-device model read a short excerpt from files",
                       isOn: $appState.settings.allowLocalContentReading)
                    .disabled(appState.settings.provider == .rulesOnly
                              || !appState.sortingMode.usesModel)

                Text(privacyExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 520)
        .task(id: appState.settings) {
            await appState.refreshProviderStatus()
        }
        .task(id: appState.sortingMode) {
            await appState.refreshProviderStatus()
        }
    }

    private var privacyExplanation: String {
        guard appState.sortingMode.usesModel else {
            return "Sorting by type reads filenames and extensions. No file is opened and no model runs, whatever is set above."
        }
        switch appState.settings.provider {
        case .rulesOnly:
            return "Hoot only looks at filenames, sizes and dates. No file is ever opened."
        case .appleOnDevice:
            return appState.settings.allowLocalContentReading
                ? "Excerpts stay on this Mac — Apple's model runs locally and nothing is uploaded. Only the first page or so of text documents is read."
                : "Only filenames, sizes and dates are analyzed. Files are never opened."
        }
    }
}

/// One sorting mode, shown as the folders it would produce.
///
/// A radio button would have fitted the form, but the choice is between two
/// pictures of a folder, and a picture is the thing being chosen. The card
/// shows three folder names in that mode's own vocabulary, which is a more
/// honest preview than either label alone.
private struct SortingModeCard: View {
    let mode: SortingMode
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    private var sampleFolders: [String] {
        switch mode {
        case .byMeaning: return ["Cebu Trip", "Finance", "Thesis"]
        case .byType: return ["Screenshots", "Images", "Spreadsheets"]
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sampleFolders, id: \.self) { name in
                        HStack(spacing: 5) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.tint)
                            Text(name)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))

                HStack(spacing: 5) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        .font(.system(size: 11))
                    Text(mode.title)
                        .font(.callout.weight(.medium))
                }

                Text(mode.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? AnyShapeStyle(.quinary) : AnyShapeStyle(Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(mode.tradeoff)
    }
}
