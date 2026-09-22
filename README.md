# Hoot

A macOS menu bar app that tidies a folder by working out what files are *about*,
not what type they are.

A boarding pass, a hotel booking and an itinerary become one trip folder.
A spreadsheet of tax records goes to Finance even though its name says nothing.
A photo with a meaningless camera-roll name is read with OCR to find out what
it shows.

If that is more than you want, it will also just put the screenshots in
Screenshots.

Everything runs on this Mac. There is no account, no server, and no network
code in the project at all.

## How it works

```
watch folder → analyse → group → review → move (reversible)
```

Nothing moves until you approve it. Every move can be undone, and Hoot never
deletes anything.

In the review window and at the notch, **hold a row to preview the file** —
Quick Look opens it the way the Finder does. The filename is often what failed to say what a file
is, so being able to look inside is usually what settles whether a suggestion
is right.

The menu bar mark carries the count, so a folder filling up is visible without
opening anything.

### Two ways to sort

**By meaning** is the one above: folders named after subjects. It reads inside
files and takes a few seconds.

**By type** names folders after what files are — Screenshots, Images, PDFs,
Spreadsheets, Videos, Audio, Archives, Installers. It decides from the filename
and extension alone, which means it is instant, never opens a file, and reaches
no model at all. Screenshots get their own folder because nothing but the name
separates one from a photograph, and they arrive in volume.

Files whose type Hoot doesn't recognize are left where they are rather than
swept into an "Other" folder. Moving something into a junk drawer named by the
app is worse than not moving it.

Switch between them in the menu bar popover or in Settings, where each mode is
shown as the folders it would produce rather than described.

### Names that say nothing

A file called `32131231231.pdf` or `ASJKDHASDASD.png` is the case Hoot is
built for, and moving it to the right folder only half-solves it — you still
cannot find it. Switch on **Rename files whose names say nothing** in
Settings and Hoot proposes a real name, taken only from text actually read
out of the file.

A name you chose is never touched: `CV.pdf` is short, vowel-poor and
completely meaningful, and Hoot leaves it alone. Every rename is shown before
it happens with the sentence saying where the name came from, can be refused
on its own, and is put back by undo.

### The notch shelf

On a Mac with a camera housing, the shelf puts your folders at the notch. Switch it
on once from the menu bar popover — **Notch HUD**, or ⌘J while that menu is open,
which is where the shortcut lives rather than being system-wide. At rest it
is a bar the height of the menu bar, reaching far enough past the camera to
show the Hoot mark on one side and the name of the folder it is showing on the
other. Point at it and it opens — whether or not anything needs filing.

Each row is a file with its size and how long it has been there, newest first,
folders leading the way the Finder does. Click a row to pick it, then:

| | file | folder |
|---|---|---|
| **space** | preview it, the same panel the Finder opens | open it where it stands |
| **hold** | the same as space | the same as space |
| **▶ triangle** | — | the same as space |
| **double-click** | open it in whatever owns it | go into it |
| **drag** | carry it out to another app or a Finder window | the same |
| **right-click** | open, or show in the Finder | open here, go into, or show in the Finder |
| **escape** | put the row down, then shut the open folders, then go up a level | |

**Space opens a folder where it stands.** Its contents appear indented
underneath it and the list you were looking at stays exactly where it was —
the Finder's list view, and for the Finder's reason: "what is in there" is
almost always asked *while* looking at something else. Press space again and
it shuts, along with anything you opened inside it. Four levels deep, after
which a folder is somewhere to go rather than something to open in place.

**Double-click goes in.** A line appears above the list saying how far in you
are, with **Up** beside it, and clicking the trail goes all the way back to
the tab. You can never climb above the folder you added: that is the one the
sandbox granted, and its parent was not.

A file that is in iCloud and not downloaded is not opened by any of these.
Opening it would start a download you did not ask for, which is safety rule 5.
Show it in the Finder and the download is your own doing.

Sort by date, name or size with the control in the corner.

Add folders with the **+** beside the tabs — Desktop, Documents, Downloads and
Pictures are offered there by name, and *Choose Folder…* takes any other. To
take one off, right-click its tab. **Three at a time**, because three names fit
across the panel at a size you can still read, and a tab shortened to `Docu…`
has stopped saying which folder it is.

**Point at a tab and that folder is listed** — no click needed, which is the
whole gesture the notch is built on carried one level in: you opened the panel
by pointing at the housing, and you change folder by pointing at a name. It
waits a moment first, because the way to the **+** runs across the tabs and
crossing one is not the same as stopping on it. Clicking still works, and is
immediate.

Swipe sideways across the panel or press **⌃⌥←** / **⌃⌥→** to move between
them as well; the keys are registered only while the panel is open, so they
belong to whatever you are working in for the rest of the time.

Hoot only ever *reads* these folders. It never moves, renames or deletes
anything in them — that is what lets there be several of them, while the one
folder it organizes stays one. See
[docs/decisions/0003](docs/decisions/0003-many-folders-read-one-folder-written.md).

Pointing at the notch never takes keyboard focus, which is what lets you open
it mid-sentence. *Clicking* a row does, because a spacebar can only reach a
window that has it — and a preview shortcut that typed a space into your
document instead would be worse than no shortcut at all.

When the folder on screen is the one Hoot watches, a **Tidy** button appears
with the number of files it would file. It opens the review window: the notch
shows you what is there, and deciding where things go stays where it was.

Needs a display with a notch. Everywhere else the menu bar popover is the
whole interface, and it is a good one.

The resting bar reaches 88pt past the cutout on each side, into menu bar that
is genuinely usable — so an app whose menu titles run past about 40% of the
screen width has the last of them covered. Finder's reach 26%. This is the
one part of the design that takes something from another app, and it is the
price of the bar saying which folder it is on rather than being invisible.

To see what the panel thinks is happening — it is the one surface here that
screen capture cannot photograph, being a floating panel of an `LSUIElement`
app — run it with its tracing on:

```bash
./Packaging/trace-hud.sh
```

### What decides where a file goes

Sorting by meaning draws on four sources of evidence, in order of how much
they are trusted:

1. **Your corrections.** Drag a file to a different folder in the review
   window and Hoot records it, weighted more heavily than anything inferred.
2. **Your existing folders.** Files already sitting in `Finance` are labelled
   examples of what you mean by finance, learned with a naive-Bayes classifier.
3. **Filename and content.** Text is read out of PDFs, Word files,
   spreadsheets, archive listings — and out of images and scans via OCR.
4. **On-device AI.** Apple's local model groups related files and suggests
   folders, with every suggestion validated before it is acted on.

Confidence is built from agreement between these, never from a model grading
itself — see [docs/pim-design-notes.md](docs/pim-design-notes.md).

## Getting it

[**Download Hoot 0.6.0**](https://github.com/codeficklefish/Hoot/releases/latest) · 1.2 MB · or read
[the landing page](https://hoot-mac.netlify.app).

**This build is not notarized by Apple.** macOS will refuse the first launch —
open **System Settings → Privacy & Security** and click *Open Anyway*. The
[release notes](https://github.com/codeficklefish/Hoot/releases/tag/v0.6.0)
give the steps. Notarizing needs an Apple Developer ID, which this project does
not have yet.

## Requirements

- macOS 13 or later, Apple silicon
- macOS 26 with Apple Intelligence for the AI features; below that Hoot falls
  back to filename rules and says so

Hoot runs on macOS today. It is structured for Windows — the rules that decide
where a file belongs are a separate module that imports nothing platform-
specific — but the Windows adapters and interface are not written yet. See
[docs/decisions/0001](docs/decisions/0001-engine-and-platform-adapters.md).

## Building

Full Xcode is required — the Command Line Tools alone are not enough, and
neither is a toolchain from swift.org. `AppleOnDeviceProvider` uses the
`@Generable` and `@Guide` macros, which Swift expands with a compiler plugin
that Apple ships only inside Xcode. Without it the build fails on

```
external macro implementation type 'FoundationModelsMacros.GenerableMacro'
could not be found
```

which points at the macro rather than at the missing toolchain, so it is worth
knowing in advance. If Xcode is installed but the build still fails this way,
check that it is the active developer directory:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

That is not the only way to end up with the wrong compiler, and the other way
is harder to read. `swift` on `PATH` is often *not* Xcode's — swiftly,
swiftenv, asdf and the swift.org installer all put their own ahead of it — and
a swift.org toolchain driving Xcode's SDK fails quite differently:

```
error: unknown argument: '-target-arch-variant'
error: cannot find 'Data' in scope
```

thousands of times, in files whose first line imports Foundation. Nothing in
that names the toolchain. Every script here resolves Xcode's Swift itself
rather than trusting `PATH` — see `Packaging/find-swift.sh` — so
`./Packaging/build-app.sh` and both `run.sh` scripts are unaffected by it. Only
running `swift` by hand is, and `xcrun swift` is the version that always means
Xcode's.

Your editor picks `swift` off `PATH` too, and gets the same wrong answer — a
language server on a swift.org toolchain reports thousands of errors like
`cannot find 'Data' in scope` in files whose first line is `import Foundation`.
Measured on one machine: zero errors with Xcode's compiler, 4811 with the one
on `PATH`. `.vscode/settings.json` pins `swift.path` to Xcode's toolchain for
that reason; reload the window after changing it, because diagnostics are
cached.

Then:

```bash
./Packaging/build-app.sh release   # produces build/Hoot.app
```

Hoot is a menu bar app with no Dock icon — look for the mark in the menu bar
after launching.

### Releasing

Distribution needs an Apple Developer ID; Gatekeeper blocks anything else, so
`release.sh` refuses to run without one rather than produce a download that
looks finished and is then refused.

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=hoot-notary \
./Packaging/release.sh            # signs, notarizes, staples, builds a DMG
```

Until there is one, releases are built through the deliberate exception, which
makes the same disk image without the signature:

```bash
ALLOW_UNSIGNED=1 ./Packaging/release.sh
```

That is how v0.6.0 was built, and why it needs the Privacy & Security step
above.

## Checking it works

```bash
swift test              # the engine imports nothing platform-specific
./Verification/run.sh   # 583 behaviour and safety checks, in a sandbox
./Evaluation/run.sh     # accuracy against folders you organized yourself
```

The evaluation measures three things, and names one on the command line to
run it alone:

| | |
|---|---|
| `folders` | does a file end up where you would have put it? |
| `meaningless` | which of the names you kept would Hoot offer to overwrite? |
| `names` | can Hoot recover a name you chose, from the file's text alone? |

The last two need no labelling and no judgement call. Every filename in a
folder you organized is a name you have already approved, so a name Hoot
would replace is a candidate mistake; and for `names`, your own filename is
hidden and then used as the answer key, because you wrote it while looking at
the file.

The verification suite covers the safety rules directly: that a symlinked
folder cannot move files outside the watched directory, that a malformed
archive cannot exhaust memory, that model output cannot produce a path like
`../../Escape`, and that undo restores a folder exactly.

It also checks the engine's own DEFLATE decoder against the system one over
real archives, byte for byte — a second implementation being the only honest
way to know a decompressor is correct.

## Repository layout

| | |
|---|---|
| `Sources/HootKit` | the engine — decides where files belong, imports only Foundation |
| `Sources/HootPlatformMac` | Apple adapters (PDFKit, Vision, FoundationModels) |
| `Sources/Hoot` | the macOS app |
| `Verification` | 583 behaviour and safety checks |
| `Evaluation` | measures accuracy against folders you organized |
| `Packaging` | app bundle, icon, signing, notarization and toolchain selection |
| `CONTEXT.md` | what each term in the code means, in one place |
| `Website/public` | the deployed landing page — what Netlify publishes |
| `Website` | design artboards the page was drawn from |
| `docs` | architecture, privacy, coding standards, and the decisions behind them |
| `.github/workflows` | builds and runs both suites on every push and PR |
| `.vscode` | editor toolchain and debug configuration |

## Design notes

[docs/pim-design-notes.md](docs/pim-design-notes.md) records why Hoot is built
the way it is, drawing on Bergman & Whittaker's *The Science of Managing Our
Digital Stuff* — including the finding that people retrieve badly from folders
someone else organized, which is the reason correcting Hoot is treated as the
most valuable signal it has.

Decisions that shaped the code are recorded as they were made, with the reason
rather than the conclusion:

- [0001](docs/decisions/0001-engine-and-platform-adapters.md) — why the engine
  is a separate module that imports nothing platform-specific.
- [0003](docs/decisions/0003-many-folders-read-one-folder-written.md) — why
  the notch may show any number of folders while Hoot still organizes one.
- [0002](docs/decisions/0002-no-protocol-for-rule-based-classification.md) —
  why a protocol with one implementation was deleted rather than kept for a
  second that never came.

[docs/coding-standards.md](docs/coding-standards.md) covers the rest.

## Releasing

[docs/launch.md](docs/launch.md) is what stands between this repository and a
build somebody else can run: the Apple Developer account that everything else
waits on, the notch interactions no check can cover, the page's claims that
stop being true the day the shelf ships, and the three things the missing
network entitlement costs — no update check, no crash reports, no numbers.

## Privacy

The full policy is [docs/privacy.md](docs/privacy.md). In short:

- No network code exists in this project — and the app ships without the
  `com.apple.security.network.client` entitlement, so macOS will not let it
  open a connection at all.
- File contents are read only on this Mac, only by the local model, and only
  with content reading enabled in Settings.
- Sorting by type reads filenames and extensions and nothing else. No file is
  opened and no model runs, whatever else is set.
- Files stored in the cloud but not downloaded are never opened, so Hoot
  cannot trigger a download you did not ask for.
- The operation log and learned model live in the app's container, readable
  only by you.

## Licence

MIT — see [LICENSE](LICENSE).
