# Architecture

The map to read before touching anything. The goal of this layout is **low
cognitive load**: you should be able to hold the whole thing in your head.

## The whole system in one picture

```
   Folder  ───▶  Engine (HootKit)  ───▶  Plan  ───▶  You approve  ───▶  Files move
   watched      what belongs where       a proposal    nothing moves      reversibly
                                                       before this
```

Three parts. **HootKit** decides where files belong and knows nothing about any
operating system. **HootPlatformMac** answers the things the engine cannot do
alone — read a PDF, recognise words in a picture, watch a folder. **Hoot** is
the macOS app: it wires one to the other and draws the interface.

## Guiding principles

- **The engine depends on nothing.** Business rules sit at the centre; the
  frameworks sit at the edge and point inward. A test enforces this, because
  the failure it prevents is invisible on a Mac.
- **Deep modules.** Prefer a simple interface over a powerful implementation.
  `ProjectDetecting` is one method; the model prompting, the validation and the
  rule-based fallback are all hidden behind it.
- **Nothing moves without approval, and everything is reversible.** Every design
  choice defers to this. Where a rule and the model disagree, the safer reading
  wins.
- **Add structure when a second case earns it.** The three-target split was not
  worth its cost with one platform; a second platform is what earned it. The
  converse holds too: a protocol with one implementation and a caller that steps
  around it is deleted — see [ADR-0002](decisions/0002-no-protocol-for-rule-based-classification.md).

## Layout

```
Sources/
├── HootKit/                 THE ENGINE — Foundation only
│   ├── Models/              what a file, a plan and an operation are
│   ├── Services/
│   │   ├── FileAnalyzer/    what is eligible; what lives only in the cloud
│   │   ├── Classifier/      rules, confidence, and refining with a model
│   │   ├── Grouping/        which files belong together
│   │   ├── Curation/        which versions are superseded
│   │   ├── Organizer/       the plan, and carrying it out safely
│   │   ├── History/         what was moved, so it can be undone
│   │   ├── Learning/        how this person files things
│   │   └── Announcing/      when Hoot speaks up, and when it stays quiet
│   ├── AI/                  the provider seam, and validating what it says
│   ├── Platform/            what the engine needs an OS to do for it
│   └── Utilities/
├── HootPlatformMac/         APPLE ADAPTERS — the only Apple imports
└── Hoot/                    THE macOS APP — SwiftUI, and the wiring
```

### The dependency rule

```
   Hoot  ─▶  HootPlatformMac  ─▶  HootKit
   (UI)      (Apple frameworks)   (pure rules — imports no framework)
```

Nothing in `HootKit` may import AppKit, SwiftUI, PDFKit, Vision,
FoundationModels, ImageIO, CoreGraphics, UserNotifications,
UniformTypeIdentifiers or Compression. `Tests/HootKitTests` fails the build if
it does. See [ADR-0001](decisions/0001-engine-and-platform-adapters.md).

### What the engine asks of a platform

Declared in `HootKit/Platform/PlatformCapabilities.swift`:

| Protocol | macOS | Windows |
|---|---|---|
| `TextExtracting` | PDFKit + Vision OCR | a PDF library + Windows.Media.Ocr |
| `ArchiveInflating` | Compression | zlib |
| `FileWatching` | `DispatchSource` | `ReadDirectoryChangesW` |
| `FolderAccessing` | a security-scoped bookmark | a stored path |
| `Notifying` | `UserNotifications` | toast notifications |
| `AIProvider` | Apple's on-device model | rules, or a local model |

Adding Windows means adding a target of adapters beside `HootPlatformMac`. It
does not mean editing the engine.

## Checking it

```bash
swift test              # the dependency rule
./Verification/run.sh   # 236 behaviour and safety checks
./Evaluation/run.sh     # accuracy against folders you organized yourself
```

The verification suite links the shipping modules rather than a copy, so it
cannot drift from what the app actually runs.
