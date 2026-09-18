# Landing page

    public/index.html   the site — this is what Netlify deploys
    Main.dc.html        design source, desktop width
    Mobile.dc.html      design source, phone width
    Phone.dc.html       design source, phone width
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

Keep that property. The privacy section tells people the app reaches nothing;
a page that pulls in a script, an analytics tag or an embedded video player
makes that sentence read as marketing on the one page where it has to read as
fact. A walkthrough video, if there is one, is self-hosted for the same reason.

Serve it locally with:

    python3 -m http.server 4173 --directory Website/public

## What the app actually does

The deployed page describes release 0.5.0 and predates two features. Anything
designed from the page alone will be a release behind, so this is the current
product.

**Hoot watches one folder and works out what files are *about*.** A boarding
pass, a hotel booking and an itinerary become one trip folder. It reads inside
documents, spreadsheets and archives, and reads the words in photos and scans
with Vision. Nothing moves until you approve it, every move can be undone, and
nothing is ever deleted.

**Two ways to sort.** *By meaning* is the above. *By type* names folders after
what files are — Screenshots, Images, PDFs, Spreadsheets — decided from the
filename and extension alone, so it is instant, opens no file and reaches no
model.

**Renaming.** A file called `3721984.pdf` is the case Hoot is built for, and
the right folder only half-solves it. Switch renaming on and Hoot proposes a
real name, taken only from words genuinely read out of the file — never from
the old name, never from a guess about a picture. A name you chose is never
touched. Every rename is shown first and undone with the move.

**The notch shelf — not released yet.** On a Mac with a camera housing, ⌘J
puts your folders at the notch. At rest it is a bar the height of the menu bar
showing the Hoot mark and the name of the folder it is on; point at it and it
opens into a list of that folder's files. Up to three folders, added from a
**+** beside the tabs; point at a tab and that folder is listed. A file
previews on space and opens on double-click; a folder has a triangle and opens
*in place*, its contents indented beneath it, while a double-click goes into
it with a trail and a way back. Drag carries a file out.

This is on `notch-file-shelf` and is in no release. **Do not put it on the
page yet.** It is described here because the page will need it next and
because it is what makes the one-folder sentence below false — the claim has
to change when this ships, not before.

**Hoot only reads shelf folders.** It organizes one folder and reads any
number you put on the shelf — it never moves, renames or deletes anything in
them. That asymmetry is what makes several folders safe, and it is the most
important thing for the privacy section to get right.

## Claims that have to be exactly true

Everything on the page is real: the filenames and folder names come from
actual runs against a Downloads folder, and the entitlements listed in the
privacy section are the ones in `Packaging/Hoot.entitlements`.

**The entitlements are unchanged and still exactly these three:**

    com.apple.security.app-sandbox
    com.apple.security.files.user-selected.read-write
    com.apple.security.files.bookmarks.app-scope

There is no network entitlement, so macOS will not let the app open a
connection at all. "Cannot, not does not" is the page's strongest claim and it
is still true.

## What the page currently gets wrong

- **The one-folder promise — only once the shelf ships.** The hero says "Hoot
  watches one folder" and the privacy section says "macOS grants access to
  that folder alone. Hoot has no way to see anything else on your Mac." Both
  are still true of the *released* build, and both stop being true the moment
  the notch shelf is released.
  `docs/privacy.md` has the replacement wording: one folder organized, any
  number read, never written. Say that the entitlements did not change —
  `files.user-selected.read-write` and `files.bookmarks.app-scope` already
  meant "whatever you pick, however many times" — or a promise that grew
  reads as a promise being walked back.

- **The version and the download links.** The page says 0.5.0 in two places
  and its four release links are pinned to `v0.5.0`. `v0.6.0` has been public
  since 12 September with its own `Hoot.dmg`, so the page is actively handing
  out a superseded build. `releases/latest/download/Hoot.dmg` and
  `releases/latest` resolve to whatever is newest and cannot rot again; the
  printed version number is written by hand and still has to be updated when a
  release is cut.

- **Nothing about renaming.** The word does not appear on the page once, and
  renaming shipped in 0.6.0 — it is the answer to the page's own opening line
  ("a filename is often the least informative thing about a file"), and the
  page currently only solves half of it by moving the file to a good folder
  while leaving it called `3721984.pdf`.

- **Nothing about sorting by type.** Also absent — no "Screenshots", no
  "by type", no mention that there is a mode which opens no file and reaches
  no model. That is the mode with the strongest privacy story of the two, and
  the page's privacy section does not know it exists.

- **Nothing about the notch**, correctly for now: 0.6.0 *removed* the old
  Dynamic Island HUD and the shelf that replaced it is unreleased. There is
  nothing to add here until it ships.

- **Mobile.** At 375px the page overflows horizontally by about nine points —
  two `.wrap` elements, most likely `.split`'s `minmax(320px, 1fr)` against
  the gutters. Worth fixing in any redesign rather than carrying over.

## Things that are still accurate

- **"Apple silicon"** in the hero — true only while the build is arm64-only.
  Build a universal binary and that line comes out.
- **The unsigned-build warning** under the download button. Distribution needs
  an Apple Developer ID, which this project does not have, so Gatekeeper
  refuses the first launch and the page is right to say so. Delete it when a
  notarized build exists rather than leaving it to rot.
- **Confidence comes from independent signals agreeing**, never from the model
  rating its own answer. Still true, and more so than when it was written.

## The artboards

`.dc.html` files are plain HTML with inline styles, authored for Claude
Design's canvas editor but readable on their own. They were the original
source for the page and are kept as the design reference. The published
canvas: <https://claude.ai/code/artifact/d69a53e3-f9e3-4809-a43f-1241a149dd75>

They still contain the square-bracket placeholders described above, and they
carry the one-folder sentence verbatim — so a page regenerated from them
reintroduces the wrong claim. Fix them alongside `public/index.html`, not
afterwards.

The app's own design system lives in a separate Claude Design project under
`_ds/hoot-design-system-…/tokens/*.css`. `public/styles.css` copies those
token values verbatim rather than re-deriving them, so the shipped page and
the design project agree on every colour, radius and duration. Keep that:
where a value exists as a token, use the token's value.
