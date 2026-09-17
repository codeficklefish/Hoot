# Privacy

Hoot reads your files to work out where they belong. This page says exactly
what it reads, what it keeps, and what leaves your Mac.

Nothing leaves your Mac.

## Hoot cannot reach the network

Not "does not" — cannot. Hoot ships under the App Sandbox, and its
entitlements are:

- `com.apple.security.app-sandbox`
- `com.apple.security.files.user-selected.read-write`
- `com.apple.security.files.bookmarks.app-scope`

There is no `com.apple.security.network.client` entitlement, which is what
macOS requires before an app may open an outgoing connection. macOS enforces
this, not Hoot's good intentions.

There is also no networking code in the project — no `URLSession`, no sockets,
no third-party libraries of any kind. Hoot has no dependencies, so nothing
else is running inside it either. The source is there to check.

There is no account, no sign-in, no server, no analytics, no telemetry, and no
crash reporting.

## What Hoot reads

**One folder it organizes.** The one you choose. Hoot stores a security-scoped
bookmark so it can reopen the same folder after a restart without asking
again. Everything Hoot *does* to a file — moving it, renaming it, putting it
back — happens inside that folder and nowhere else.

**Any number of folders it shows you.** The shelf at the notch lists folders
you add yourself, one open panel at a time. Hoot only ever reads these: it
lists what is in them, previews a file when you hold one, and hands a file to
another app when you drag one out. It never moves, renames or deletes
anything in a shelf folder. That asymmetry is the whole reason it can have
several of them.

macOS grants access to the folders you picked and to nothing else. This
needed no new entitlement, and the three above are unchanged — because
`files.user-selected.read-write` and `files.bookmarks.app-scope` already mean
"whatever you choose, however many times you choose it". The sandbox story
was always this; the app simply asked for one folder before and asks for as
many as you offer now.

**Always:** filenames, file sizes, and creation and modification dates.

**When "let the on-device model read a short excerpt from files" is on** — a
setting you control, on by default:

- Text from documents: PDFs, Word files, spreadsheets, plain text, and the
  listings inside archives.
- Text and scene descriptions from images, read with Apple's Vision framework
  on your Mac. A photographed receipt or a screenshot of a booking can be
  filed by what it says.

Turn that setting off and Hoot uses filenames, sizes and dates alone.

## What Hoot keeps, and where

In `~/Library/Application Support/`:

- **Operation history** — what was moved where, so moves can be undone.
- **Corrections** — when you drag a file to a different folder in the review
  window, so Hoot learns how you file things.
- **A learned classifier** — counts derived from your existing folders.

In the app's preferences (`UserDefaults`): your settings, the bookmark for
the watched folder.

All of it is on your Mac, and all of it is removed when you delete the app's
Application Support folder. Clearing history from Settings removes the
operation log at any time.

## Apple Intelligence

When "Analyze with Apple Intelligence" is selected, Hoot uses Apple's
on-device foundation model through the FoundationModels framework, which runs
on your Mac. Hoot sends nothing anywhere itself; that model's own behaviour is
governed by [Apple's privacy policy](https://www.apple.com/legal/privacy/).

Select "Filename rules only" and no model is used at all.

## Renaming

Hoot can rename files whose names say nothing — a camera number, a row of
digits, a keyboard mash. **It is off until you turn it on**, in Settings, and
it changes what file content is used for, so it is worth saying exactly what
it does.

- A name comes **only from text actually read out of the file**. Never from
  the old filename, which is the thing that failed, and never from a guess
  about a picture: words read off a photographed receipt can become a name,
  "appears to show: outdoor, sky, water" cannot.
- **A name you chose is never touched**, and never even sent. Files whose
  names already say something are filtered out before the model sees the
  request.
- It needs the on-device model and needs excerpt reading enabled. With
  filename rules only, or with content reading off, nothing is renamed and
  Settings says which one is missing.
- **Sorting by type never renames anything.** It does not open files, so it
  has nothing to name them from.
- Every rename is shown before it happens — the old name, the new one, and
  the sentence saying what in the text it came from. You can refuse one on
  its own and keep the move.
- A rename is a move, so it is in the operation history and **undo puts the
  original name back**.

The file never leaves your Mac, and the model that reads it is the same local
one described above.

## What Hoot does to your files

It moves them, and renames them if you asked it to, and only after you
approve. It never copies-and-
deletes, never overwrites — a name collision gets a free variant instead — and
**it never deletes anything.** Every batch can be undone, and undo refuses to
put a file back on top of something that has since taken its place.

The only thing Hoot removes is a folder it created itself, when undo leaves it
empty. It cannot remove a folder you already had.

None of this applies to the folders on the shelf. Nothing in this section can
happen to one of those, because nothing in Hoot writes to them at all — the
shelf lists, previews and hands over, and that is the entire set of verbs it
has. See [decision 0003](decisions/0003-many-folders-read-one-folder-written.md).

## Children

Hoot collects nothing from anyone, of any age.

## Changes

This page is versioned in the repository alongside the code it describes, so
its history is public and any change is visible in the commit log.

_Last reviewed: 17 September 2026._
