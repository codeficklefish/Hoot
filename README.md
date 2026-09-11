# Hoot

A macOS menu bar app that tidies a folder by working out what files are *about*,
not what type they are.

A boarding pass, a hotel booking and an itinerary become one trip folder.
A spreadsheet of tax records goes to Finance even though its name says nothing.
A photo with a meaningless camera-roll name is read with OCR to find out what
it shows.

Everything runs on this Mac. There is no account, no server, and no network
code in the project at all.

## How it works

```
watch folder → analyse → group → review → move (reversible)
```

Nothing moves until you approve it. Every move can be undone, and Hoot never
deletes anything.

### What decides where a file goes

Four sources of evidence, in order of how much they are trusted:

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

Then:

```bash
./Packaging/build-app.sh release   # produces build/Hoot.app
```

Hoot is a menu bar app with no Dock icon — look for the mark in the menu bar
after launching.

### Releasing

Distribution needs an Apple Developer ID; Gatekeeper blocks anything else.

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=hoot-notary \
./Packaging/release.sh            # signs, notarizes, staples, builds a DMG
```

## Checking it works

```bash
swift test              # the engine imports nothing platform-specific
./Verification/run.sh   # 236 behaviour and safety checks, in a sandbox
./Evaluation/run.sh     # accuracy against folders you organized yourself
```

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
| `Verification` | 236 behaviour and safety checks |
| `Evaluation` | measures accuracy against folders you organized |
| `Packaging` | app bundle, icon, signing and notarization |
| `Website` | the landing page source |
| `docs` | architecture, standards, and the decisions behind them |

## Design notes

[docs/pim-design-notes.md](docs/pim-design-notes.md) records why Hoot is built
the way it is, drawing on Bergman & Whittaker's *The Science of Managing Our
Digital Stuff* — including the finding that people retrieve badly from folders
someone else organized, which is the reason correcting Hoot is treated as the
most valuable signal it has.

## Privacy

- No network code exists in this project.
- File contents are read only on this Mac, only by the local model, and only
  with content reading enabled in Settings.
- Files stored in the cloud but not downloaded are never opened, so Hoot
  cannot trigger a download you did not ask for.
- The operation log and learned model live in the app's container, readable
  only by you.

## Licence

MIT — see [LICENSE](LICENSE).
