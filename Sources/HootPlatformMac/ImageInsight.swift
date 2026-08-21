import Foundation
import Vision
import CoreGraphics
import ImageIO
import HootKit

/// Works out what an image is *of*, so that a file whose name says nothing
/// still carries evidence.
///
/// A photo called `301847592_118273640591827_4472910385562931_n.jpg` has no
/// readable name and, without this, no content either — leaving Hoot to either
/// guess or file it under "Images" and hope. Vision runs entirely on-device,
/// so reading the picture costs no privacy.
///
/// Two signals, deliberately weighted differently:
/// - **Text found in the image** is strong. A photographed receipt, a
///   screenshot of a booking, a slide — the words mean what they say.
/// - **Scene labels** are weak and can be confidently wrong. Hoot's own owl
///   icon classifies as "night_sky / moon" at 49%. Only labels the model is
///   reasonably sure of are used, and they are phrased as impressions.
public struct ImageInsight {
    public init() {}


    /// Below this, labels are more likely to mislead than to help.
    private static let minimumLabelConfidence: Float = 0.5
    private static let maximumLabels = 4
    /// Recognition doesn't improve above this, and downscaling keeps big
    /// photos fast.
    private static let maximumPixelSize = 1600

    public struct Result {
        let description: String
        /// True when actual words were read out of the picture. Scene labels
        /// alone are an impression, not text, and are held to a lower status.
        let containsRecognizedText: Bool
    }

    /// What can be established about the image, or nil when nothing
    /// trustworthy was found.
    public func describe(_ url: URL) -> Result? {
        guard let image = loadImage(at: url) else { return nil }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        var parts: [String] = []
        let text = recognizedText(handler: handler)

        if let text, !text.isEmpty {
            parts.append("Text in image: \(text)")
        }
        if let labels = sceneLabels(handler: handler), !labels.isEmpty {
            parts.append("Appears to show: \(labels.joined(separator: ", "))")
        }

        guard !parts.isEmpty else { return nil }
        return Result(
            description: parts.joined(separator: ". "),
            containsRecognizedText: !(text ?? "").isEmpty
        )
    }

    /// Reads any words in an already-decoded image. Used for scanned PDF
    /// pages, which are pictures of text.
    public func recognizeText(in image: CGImage) -> String? {
        recognizedText(handler: VNImageRequestHandler(cgImage: image, options: [:]))
    }

    private func recognizedText(handler: VNImageRequestHandler) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        guard (try? handler.perform([request])) != nil else { return nil }

        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // A stray character or two is noise, not content.
        guard text.count >= 3 else { return nil }
        return String(text.prefix(TextExtractor.excerptLength))
    }

    private func sceneLabels(handler: VNImageRequestHandler) -> [String]? {
        let request = VNClassifyImageRequest()
        guard (try? handler.perform([request])) != nil else { return nil }

        return (request.results ?? [])
            .filter { $0.confidence >= Self.minimumLabelConfidence }
            .prefix(Self.maximumLabels)
            // Identifiers arrive as "interior_room"; make them readable.
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
    }

    /// Loads the image, downscaled, so a 4000px photo doesn't cost more than
    /// it needs to.
    private func loadImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.maximumPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
