# ADR-0002: No protocol between the pipeline and rule-based classification

- **Status:** Accepted
- **Date:** 2026-09-11

## Context

`FileClassifier` was a nine-line protocol with one method:

```swift
public protocol FileClassifier {
    func classify(_ file: FileItem) async throws -> ClassificationResult
}
```

Its doc comment described it as *"the single seam between Hoot's file pipeline and
whatever does the actual thinking about where a file belongs — a rule-based
fallback today, a local or remote AI model later."*

That future arrived, and it did not arrive here. A model that reconsiders where a
file belongs goes through `AIProvider` → `CategoryRefiner`, which reads text out of
the file, asks the provider, and arbitrates the answer against the rules. The
seam that was supposed to be reserved for "the AI one later" was built somewhere
else, for good reasons, and `FileClassifier` was left describing a plan that had
been superseded.

What was left behind had three marks of a seam nothing varies across:

- **One conformer**, `RuleBasedClassifier`, and one injection site — `AppState.init`,
  whose default was never overridden by anything, including the verification suite.
- **The useful method was not on it.** `classify(_:excerpt:)` is what carries the
  interesting behaviour, because text read from inside a file is an independent
  signal that raises confidence. It was never a protocol requirement, so
  `CategoryRefiner` constructed its own concrete `RuleBasedClassifier` rather than
  going through the seam. The one caller that did real classification work stepped
  around it.
- **It imposed `async throws` on code that is neither.** The conforming method
  existed only to satisfy the protocol:

  ```swift
  public func classify(_ file: FileItem) async throws -> ClassificationResult {
      classify(file, excerpt: nil)
  }
  ```

  Classification is synchronous string work over ten keyword lists. The `async`
  forced a detached `Task` and a hop back to the main actor in `ingest`, and the
  `throws` required a `UserFacingIssue` failure branch that could not be reached.
  The verification suite paid for it too, bridging back to synchronous code with
  `DispatchSemaphore` in places where classification was the only asynchronous
  thing happening.

## Decision

Delete `FileClassifier`. `AppState` holds a concrete `RuleBasedClassifier`, and
both callers use `classify(_:excerpt:)`.

The rule this applies: **one adapter means a hypothetical seam, two means a real
one.** `ProjectDetecting` has two conformers, `ArchiveInflating` has two, and
`AIProvider` has one in production plus four in the suite. Those seams are real.
This one had one conformer and a caller that avoided it.

## Consequences

**Good.** `ingest` classifies inline, so a file's badge appears in the same frame
as its row rather than a task hop later. The unreachable failure branch is gone.
Three of the suite's eight `DispatchSemaphore` bridges went with it — the ones
that existed only because classification was needlessly asynchronous. The
remaining five wrap work that genuinely is.

**Costs.** Swapping in a different rule-based classifier now means editing the
type rather than passing a different one. That was already true in practice: the
default was never overridden anywhere.

**Not addressed here.** This says nothing about `AIProvider`, which is the real
classification seam and stays exactly as it is. Nor about a Windows port: Windows
runs the same filename rules as macOS, so this was never a platform seam and
appears in neither ADR-0001's protocol table nor `architecture.md`'s.

**If this is revisited.** The thing that would justify bringing a protocol back is
a *second* implementation that a caller actually selects between at runtime — not
the prospect of one. If that arrives, put `excerpt` on it, because that is the
method callers want.
