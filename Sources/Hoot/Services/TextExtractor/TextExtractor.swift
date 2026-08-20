import Foundation
import PDFKit

/// Pulls a short opening excerpt out of a file so a *local* model can tell
/// what it actually is. Never called for external providers — see
/// `ClassificationCoordinator`, which only requests excerpts when the active
/// provider runs on this machine.
struct TextExtractor {

    /// Enough to identify a document's subject without loading whole files
    /// into memory or flooding the model's context.
    static let excerptLength = 600

    /// Cap for formats we must load whole. Formats that can be read lazily
    /// (a PDF's first pages, a zip's directory) are exempt — a 4GB archive is
    /// still cheap to identify, and refusing it loses real signal.
    private static let maximumWholeFileSize: Int64 = 25 * 1024 * 1024

    /// Even lazy formats get an upper bound, to avoid pathological files.
    private static let maximumLazyFileSize: Int64 = 8 * 1024 * 1024 * 1024

    /// What Hoot managed to learn from inside a file.
    struct Evidence {
        let excerpt: String
        /// True when the excerpt is text that genuinely exists in the file.
        ///
        /// This distinction decides whether a file may join a project on
        /// content alone. Words on a photographed receipt mean what they say;
        /// "appears to show: outdoor, sky" is a guess about a picture, and
        /// letting a guess license project membership is how meaningless
        /// photos ended up in a "Software Development" folder.
        let isTextual: Bool
    }

    /// Convenience for callers that only need the text to show a model.
    func excerpt(for file: FileItem) -> String? {
        evidence(for: file)?.excerpt
    }

    func evidence(for file: FileItem) -> Evidence? {
        // Never open a file that is only a cloud placeholder: doing so starts
        // a download the user did not ask for, potentially a very large one.
        // The filename still has to speak for these.
        guard !file.isCloudPlaceholder else { return nil }

        guard file.fileSize <= Self.maximumLazyFileSize else { return nil }
        // .doc (legacy binary Word) is deliberately unsupported: identifying it
        // would mean running a complex binary parser over untrusted input.
        let mustLoadWholeFile = ["rtf"].contains(file.fileExtension.lowercased())
        if mustLoadWholeFile, file.fileSize > Self.maximumWholeFileSize { return nil }

        let text: String?
        switch file.fileExtension.lowercased() {
        case "pdf":
            text = pdfText(at: file.url)
        case "docx":
            text = wordText(at: file.url)
        case "rtf":
            text = rtfText(at: file.url)
        case "txt", "md", "markdown", "csv", "tsv", "json", "log":
            text = plainText(at: file.url)
        case "xlsx", "xlsm":
            text = spreadsheetText(at: file.url)
        case "zip":
            text = archiveSummary(at: file.url)
        case "png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "webp", "bmp":
            // Reading the picture itself is the only evidence an image with a
            // meaningless filename can offer.
            guard let insight = ImageInsight().describe(file.url) else { return nil }
            return Evidence(excerpt: insight.description,
                            isTextual: insight.containsRecognizedText)
        default:
            // Unknown types contribute nothing readable; the filename alone
            // has to speak for them.
            text = nil
        }

        guard let condensed = text.flatMap(Self.condense) else { return nil }
        return Evidence(excerpt: condensed, isTextual: true)
    }

    /// Text a PDF is expected to yield before it's treated as scanned.
    private static let scannedPDFTextThreshold = 40

    private func pdfText(at url: URL) -> String? {
        guard let document = PDFDocument(url: url), document.pageCount > 0 else { return nil }

        // Scan a few pages rather than just the first: books and reports often
        // open on a cover image with no text layer at all.
        var collected = ""
        for index in 0..<min(document.pageCount, 4) {
            guard let page = document.page(at: index)?.string else { continue }
            collected += page + " "
            if collected.trimmingCharacters(in: .whitespacesAndNewlines).count >= 120 { break }
        }

        let trimmed = collected.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= Self.scannedPDFTextThreshold { return collected }

        // Almost no extractable text means the pages are pictures — a scan or
        // a photographed document. The words are there, just not as text, so
        // read them the same way an image is read.
        return scannedPDFText(document: document) ?? (collected.isEmpty ? nil : collected)
    }

    /// Renders the first pages and runs recognition over them.
    private func scannedPDFText(document: PDFDocument) -> String? {
        var recognized: [String] = []
        let insight = ImageInsight()

        for index in 0..<min(document.pageCount, 2) {
            guard let page = document.page(at: index),
                  let image = Self.render(page) else { continue }
            if let text = insight.recognizeText(in: image), !text.isEmpty {
                recognized.append(text)
            }
            if recognized.joined().count >= excerptLengthLimit { break }
        }

        let combined = recognized.joined(separator: " ")
        return combined.isEmpty ? nil : combined
    }

    /// Rasterizes a page at a resolution high enough for recognition without
    /// paying for the full page size.
    private static func render(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let scale = min(2.0, 1600 / max(bounds.width, bounds.height))
        let pixelSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        guard let context = CGContext(
            data: nil,
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: pixelSize))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    /// Reads a .docx by unzipping `word/document.xml` directly.
    ///
    /// This deliberately avoids `NSAttributedString`, which was used here
    /// before: it is a large, historically CVE-prone parser, and its
    /// type-sniffing path can resolve a file as HTML, which fetches remote
    /// resources. Handing unvetted downloads to it was the riskiest thing
    /// Hoot did. The zip reader below is bounded and touches nothing but
    /// the file itself.
    private func wordText(at url: URL) -> String? {
        guard let zip = ZipReader(url: url),
              let data = zip.contents(of: "word/document.xml") else { return nil }
        let values = Self.tagValues(in: String(decoding: data, as: UTF8.self),
                                    tag: "w:t", limit: 200)
        return values.isEmpty ? nil : values.joined(separator: " ")
    }

    /// Strips RTF control words instead of handing the file to a parser.
    /// RTF is text-based, so recovering enough words to identify a document
    /// needs no format library and can't dereference anything external.
    private func rtfText(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let raw = String(decoding: data.prefix(256 * 1024), as: UTF8.self)

        var output = ""
        var skippingControlWord = false
        for character in raw {
            if output.count >= excerptLengthLimit { break }
            if character == "\\" {
                skippingControlWord = true
            } else if skippingControlWord {
                // A control word runs until the first non-alphanumeric byte.
                if !character.isLetter && !character.isNumber {
                    skippingControlWord = false
                    output.append(" ")
                }
            } else if character == "{" || character == "}" {
                output.append(" ")
            } else {
                output.append(character)
            }
        }
        // A file named .rtf isn't necessarily RTF. Strip any markup that
        // survives so the excerpt is visible text only — this keeps HTML or
        // XML disguised under a document extension from reaching the model
        // as raw tags, which is needless prompt-injection surface.
        let stripped = output.replacingOccurrences(
            of: "<[^>]{0,400}>", with: " ", options: .regularExpression
        )
        return stripped.isEmpty ? nil : stripped
    }

    private var excerptLengthLimit: Int { Self.excerptLength * 2 }

    /// Pulls text out of repeated XML elements, e.g. `<w:t>` or `<t>`.
    private static func tagValues(in xml: String, tag: String, limit: Int) -> [String] {
        var values: [String] = []
        var cursor = xml.startIndex
        while values.count < limit,
              let open = xml.range(of: "<\(tag)", range: cursor..<xml.endIndex),
              let contentStart = xml.range(of: ">", range: open.upperBound..<xml.endIndex),
              let close = xml.range(of: "</\(tag)>", range: contentStart.upperBound..<xml.endIndex) {
            let cleaned = unescapeXML(String(xml[contentStart.upperBound..<close.lowerBound]))
            if !cleaned.isEmpty { values.append(cleaned) }
            cursor = close.upperBound
        }
        return values
    }

    /// An .xlsx is a zip whose `sharedStrings.xml` holds every distinct cell
    /// string — headers and labels included. That's the most identifying text
    /// in a spreadsheet, and it's reachable without a spreadsheet engine.
    private func spreadsheetText(at url: URL) -> String? {
        guard let zip = ZipReader(url: url),
              let data = zip.contents(of: "xl/sharedStrings.xml") else { return nil }
        let xml = String(decoding: data, as: UTF8.self)

        // Headers appear first, and a sheet can hold tens of thousands of strings.
        let values = Self.tagValues(in: xml, tag: "t", limit: 40)
        guard !values.isEmpty else { return nil }
        return values.joined(separator: " · ")
    }

    /// Lists what an archive holds. The contents identify it far better than
    /// the name does — a zip wrapping a single .dmg is an app installer.
    private func archiveSummary(at url: URL) -> String? {
        guard let zip = ZipReader(url: url) else { return nil }
        let entries = zip.entries()
        guard !entries.isEmpty else { return nil }

        let names = entries.map(\.name).filter { !$0.hasSuffix("/") }
        guard !names.isEmpty else { return nil }

        if names.count == 1, let only = names.first,
           ["dmg", "pkg", "app", "exe", "msi"].contains((only as NSString).pathExtension.lowercased()) {
            return "Archive containing a single installer: \(only)"
        }

        // Where everything sits under one folder, that folder names the thing.
        let topLevel = Set(names.compactMap { $0.split(separator: "/").first.map(String.init) })
        var summary = "Archive with \(names.count) files"
        if topLevel.count == 1, let root = topLevel.first {
            summary += ", all under “\(root)”"
        }
        let sample = names.prefix(8).map { ($0 as NSString).lastPathComponent }
        return summary + ". Includes: " + sample.joined(separator: ", ")
    }

    private static func unescapeXML(_ raw: String) -> String {
        var value = raw
        for (entity, replacement) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                       ("&quot;", "\""), ("&apos;", "'")] {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        // Excel encodes control characters as _x000C_ and similar.
        value = value.replacingOccurrences(
            of: "_x[0-9A-Fa-f]{4}_", with: " ", options: .regularExpression
        )
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func plainText(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        // Read a bounded prefix so a huge log file can't be pulled into memory.
        let data = (try? handle.read(upToCount: 8 * 1024)) ?? Data()
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
    }

    /// Squashes whitespace and truncates, so excerpts stay compact and
    /// comparable regardless of the source format's layout.
    private static func condense(_ raw: String) -> String? {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count >= 12 else { return nil }
        return collapsed.count > excerptLength
            ? String(collapsed.prefix(excerptLength)) + "…"
            : collapsed
    }
}
