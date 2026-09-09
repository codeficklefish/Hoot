# Landing page

The source of Hoot's landing page, in desktop and phone widths.

These are `.dc.html` artboards — plain HTML with inline styles, authored for
Claude Design's canvas editor but readable and portable on their own. To turn
them into a website, lift the markup out of the `<x-dc>` element; it has no
framework and no build step.

The published canvas:
<https://claude.ai/code/artifact/d69a53e3-f9e3-4809-a43f-1241a149dd75>

## Before publishing it anywhere

Square-bracket text is a deliberate placeholder, not a mistake:

- `[DOWNLOAD URL]` · `[PRICE]` · `[VERSION]` · `[SIZE]` · `[SUPPORT EMAIL]`

Resolved on 9 September 2026, when the repository was made public: the GitHub
and privacy-policy links now point at real pages, and the privacy section ends
with *"the source is public, so you can check"* again — the strongest line in
it, and true once more.

One claim still to check against reality before it goes live:

- **"Apple silicon"** in the hero is accurate only while the build is
  arm64-only. Build a universal binary and that line should come out.

Everything else on the page is real: the filenames and folder names come from
actual runs against a Downloads folder.
