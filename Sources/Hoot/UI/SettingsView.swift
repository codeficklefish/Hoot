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
                    .disabled(appState.settings.provider == .rulesOnly)

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
    }

    private var privacyExplanation: String {
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
