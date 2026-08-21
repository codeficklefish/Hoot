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

- `[DOWNLOAD URL]` · `[GITHUB URL]` · `[PRIVACY POLICY URL]`
- `[PRICE]` · `[VERSION]` · `[SIZE]` · `[SUPPORT EMAIL]`

Two claims to check against reality before they go live:

- **"Apple silicon"** in the hero is accurate only while the build is
  arm64-only. Build a universal binary and that line should come out.
- The privacy section used to end *"the source is public, so you can check."*
  That sentence was removed while the repository was private. It is the
  strongest line in the section — put it back if the repository becomes public.

Everything else on the page is real: the filenames and folder names come from
actual runs against a Downloads folder.
