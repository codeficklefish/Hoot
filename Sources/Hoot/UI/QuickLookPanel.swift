import AppKit
import QuickLookUI

/// Shows a file in Quick Look, the same panel the Finder opens on space.
///
/// SwiftUI's `quickLookPreview` modifier is iOS-only, so the macOS panel is
/// driven directly. One shared instance because `QLPreviewPanel` is itself a
/// singleton — a second data source would just fight the first for it.
///
/// Hoot never reads the file to do this. Quick Look renders it out of process,
/// which is the point: it can show a PDF, a spreadsheet or a photo without the
/// app having to understand any of those formats.
final class QuickLookPanel: NSObject {
    static let shared = QuickLookPanel()

    private var url: NSURL?

    private override init() { super.init() }

    func show(_ url: URL) {
        self.url = url as NSURL
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        panel.reloadData()
        // Ordering front rather than toggling: holding a second row should
        // swap what the panel shows, not close it.
        panel.makeKeyAndOrderFront(nil)
    }
}

extension QuickLookPanel: QLPreviewPanelDataSource {
    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int {
        url == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> QLPreviewItem! {
        url
    }
}
