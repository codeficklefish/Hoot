# Landing page

    public/index.html   the site — this is what Netlify deploys
    Main.dc.html        design source, desktop width
    Mobile.dc.html      design source, phone width
    canvas.json         canvas layout for the artboards above
    *.png               marks and app icon, used by the artboards

`public/` holds the deployed site and nothing else, so a deploy publishes the
page alone — the artboards, this file and the loose images stay in the
repository without being served. `netlify.toml` at the repository root points
at it; there is no build step, and the file goes up exactly as it sits here.

## The page

`public/index.html` is one self-contained file: no framework, no bundler, no
dependencies. The only thing it fetches is its typefaces, from Google Fonts.
It declares its own charset — without that line, any host serving `text/html`
with no charset turns every em dash into mojibake, which is a bug this page
has already had once.

Serve it locally with:

    python3 -m http.server 4173 --directory Website/public

## The artboards

`.dc.html` files are plain HTML with inline styles, authored for Claude
Design's canvas editor but readable on their own. They were the original
source for the page and are kept as the design reference. The published
canvas: <https://claude.ai/code/artifact/d69a53e3-f9e3-4809-a43f-1241a149dd75>

They still contain the square-bracket placeholders described below. The
deployed page no longer does.

## Claims to keep honest

Everything on the page is real: the filenames and folder names come from
actual runs against a Downloads folder, and the entitlements listed in the
privacy section are the ones in `Packaging/Hoot.entitlements`.

Two things to revisit when the app changes:

- **"Apple silicon"** in the hero is accurate only while the build is
  arm64-only. Build a universal binary and that line should come out.
- **The unsigned-build warning** under the download button, and the version
  and size beside it, describe release v0.5.0. When a notarized build exists,
  update the version, and delete the warning rather than leaving it to rot.
