import Foundation

#if canImport(FoundationModels)
import FoundationModels
import HootKit

/// Naming files whose current names say nothing.
///
/// Separate from the grouping and category requests because it is a different
/// question with a different failure mode. Grouping wrong puts a file in an
/// odd folder; naming wrong puts a *confident invention* on a file the user
/// will later search for by what it actually is. So the instructions spend
/// most of their length forbidding the model from adding anything it was not
/// shown, and offer it an explicit way to decline.
@available(macOS 26.0, *)
extension AppleOnDeviceProvider {

    /// Fewer per request than grouping. Each file here carries an excerpt,
    /// so the prompt is much denser, and a name is short enough that the
    /// round trips cost little.
    static let maximumFilesPerNamingRequest = 8

    public func suggestNames(for files: [FileDescriptor]) async throws -> [NameSuggestion] {
        guard case .available = await availability() else {
            throw AIProviderError.unavailable("The on-device model isn't ready.")
        }

        var suggestions: [NameSuggestion] = []
        for chunk in files.chunked(into: Self.maximumFilesPerNamingRequest) {
            let session = LanguageModelSession(instructions: Self.namingInstructions)
            do {
                let answer = try await session.respond(
                    to: Self.namingPrompt(for: chunk),
                    generating: ModelNames.self,
                    options: Self.deterministic
                )
                suggestions += answer.content.files.map {
                    NameSuggestion(
                        filename: $0.filename,
                        proposedName: $0.name,
                        reason: $0.reason,
                        requestIndex: $0.number
                    )
                }
            } catch {
                throw AIProviderError.failed(error.localizedDescription)
            }
        }
        return suggestions
    }

    /// No example names anywhere in here, deliberately. Naming examples in
    /// the grouping prompt caused the model to reuse them verbatim for
    /// unrelated files, and a filename is exactly where that would be
    /// hardest to notice.
    private static var namingInstructions: String {
        """
        You give a file a name that says what it is.

        Each file's current name says nothing — a camera number, a string of \
        digits, a row of keys. You are shown the text that was actually read \
        out of the file. That text is the only thing you may name it from.

        Rules:
        - Between 2 and 6 words, written the way a person writes a filename: \
        who or what it concerns, and what kind of thing it is.
        - Write it in ordinary sentence case even when the text is in \
        capitals. Documents shout; filenames do not. Keep the capitals only \
        on names of people, places and companies.
        - Use only names, dates, places, subjects and amounts that appear in \
        the text. Invent nothing, and add nothing you merely expect to be true.
        - No file extension. No folder, no slash, no quotes.
        - If the text does not say what the file is, repeat its current name \
        exactly. That is a complete answer and it is often the right one.
        - Answer for every file, exactly once, and give each file's number \
        back with its name.
        """
    }

    /// Numbered, because the filenames here are the hard ones to copy.
    /// Asked to echo `------.txt` verbatim the model came back one dash
    /// short, and the answer was dropped as being for a file that was never
    /// sent. A number survives the round trip.
    private static func namingPrompt(for files: [FileDescriptor]) -> String {
        var lines = ["Name each of these \(files.count) files:"]
        for (offset, file) in files.enumerated() {
            lines.append("\(offset + 1). \(file.filename)")
            if let excerpt = file.excerpt, !excerpt.isEmpty {
                lines.append("    text from inside: \(excerpt)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Guided generation types

@available(macOS 26.0, *)
@Generable
private struct ModelName: Equatable {
    @Guide(description: "The number shown beside this file in the prompt")
    public let number: Int
    @Guide(description: "The file's current name, copied from the input")
    public let filename: String
    @Guide(description: "A name of 2 to 6 real words, taken from the file's own text. No extension.")
    public let name: String
    @Guide(description: "At most 12 words saying which words in the text the name came from. Not a summary of the file.")
    public let reason: String
}

@available(macOS 26.0, *)
@Generable
private struct ModelNames: Equatable {
    @Guide(description: "One entry for every input filename")
    public let files: [ModelName]
}

#endif
