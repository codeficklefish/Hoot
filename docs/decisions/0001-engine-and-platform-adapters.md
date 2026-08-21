# ADR-0001: Split Hoot into a pure engine and platform adapters

- **Status:** Accepted
- **Date:** 2026-08-20

## Context

Hoot should run on Windows as well as macOS. Today it cannot, and the reason is
structural rather than incidental: the rules that decide where a file belongs are
mixed in with the Apple frameworks that read files and draw windows.

A survey of the 44 source files found the split is better than it looks:

| | files |
|---|---|
| Already Foundation-only | 28 |
| Tied to an Apple framework | 16 (8 of them UI) |

So only eight non-UI files stand in the way — but they stand in the way completely,
because they sit *inside* the engine rather than at its edge. `TextExtractor` imports
PDFKit; `ImageInsight` imports Vision; `ZipReader` imports Apple's Compression;
`FileItem` imports UniformTypeIdentifiers. Any Windows build fails on the first import.

A second problem showed up in the same survey. `AppState.swift` had grown to **745
lines** — watching, classifying, planning, organizing, undoing, notifying, learning
and settings in one type. That is 2.5× the 300-line guideline and, more importantly,
a file with no nameable single responsibility.

## Decision

Adopt the dependency rule already proven in the ONETT project: **business rules sit at
the centre and depend on nothing; platform code sits at the edge and depends inward.**

Three targets:

```
   HootKit          the engine — Foundation only, no platform frameworks
      ▲
      │  depends inward
   HootPlatformMac  Apple adapters (PDFKit, Vision, FoundationModels, AppKit)
      ▲
      │
   Hoot             the macOS app (SwiftUI) — wires an adapter into the engine
```

`HootKit` may not import AppKit, SwiftUI, PDFKit, Vision, FoundationModels,
ImageIO, CoreGraphics, UserNotifications, UniformTypeIdentifiers or Compression.
This is checked by a test, not by good intentions.

Everything the engine needs from a platform is expressed as a protocol it owns:

| Protocol | macOS implementation | Windows implementation |
|---|---|---|
| `FileWatching` | `DispatchSource` on the directory | `ReadDirectoryChangesW` |
| `TextExtracting` | PDFKit + Vision OCR | PDF library + Windows.Media.Ocr |
| `ArchiveInflating` | Apple's Compression | zlib |
| `Notifying` | `UserNotifications` | Windows toast notifications |
| `AIProvider` | Apple on-device model | rules, or a local model |

Adding Windows then means adding one target of adapters, not editing the engine.

## Consequences

**Good.** The engine becomes testable without a Mac, and the existing verification
suite runs against it directly. A Windows port stops being a rewrite and becomes a
set of adapters. Each platform framework now appears in exactly one file, so
replacing PDFKit or the OCR engine is a local change.

**Costs.** More targets and more indirection than a single-app layout: three modules
where there was one, and a protocol between the engine and every platform call.
For a single-platform app that would be overhead not yet earned — the second
platform is what earns it.

**Not addressed here.** The user interface is not portable and is not made portable
by this change. SwiftUI stays macOS-only; Windows needs its own UI built against the
same engine. That is the real remaining cost of the port, and it is deliberately kept
out of this decision.
