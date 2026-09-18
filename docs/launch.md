# Launch

What is between here and a build somebody else can run. Free, public, and
notarized — the app does not change, the distribution does.

Each phase has an exit condition rather than a list of tasks. A phase is done
when its condition is true, and not before.

## Phase 0 — The Apple Developer account

**Exit: `security find-identity -v -p codesigning` lists a Developer ID
Application certificate, and `xcrun notarytool history --keychain-profile
hoot-notary` returns without an error.**

This is first because it is the only item with a queue in front of it.
Enrolment in the Apple Developer Program is $99/year and can take days —
individual enrolments are sometimes held for identity checks. Everything in
phases 2 onwards is blocked on it, and nothing in phase 1 is, so start this
and do phase 1 while it sits.

`Packaging/release.sh` already knows the whole sequence — sign with hardened
runtime, notarize, staple, package — and refuses by default without a
signing identity, which is the behaviour to keep. The three one-off steps are
written in its header.

Gatekeeper is not a warning you can ship past. An unsigned build tells the
person "Apple cannot check it for malicious software", and in practice they
delete it. There is no free path around this.

## Phase 1 — Use the thing

**Exit: every interaction in the notch has been performed by a human at least
once, and the trace log shows what was expected.**

Not optional, and not last. The shelf is the headline feature of this release
and no person has ever clicked a row in it. The checks cover the rules —
576 of them — and cover none of the gestures, because a check cannot hold a
mouse.

    ./Packaging/trace-hud.sh

Then point at the notch and work through these. The log names each one.

| | What should appear | What a failure looks like |
|---|---|---|
| Click a row | `clicked … picking`, instantly | a pause before the row highlights |
| Double-click a file | `clicked … paired, opening` | two `picking` lines, never a pair |
| Click a folder's triangle | `opened … at depth 0` | `clicked … picking` — the row took the click |
| Space on a file | `quick look …` and a preview | the line appears, no panel |
| Drag a row to the Desktop | `drag began` then `drag ended` | a `began` with no `ended` |
| Point at a tab | `tab N entered`, then it lists | `entered` then `left` at once |
| The **+** menu | `opening the folder picker` | nothing |

The panel cannot be screenshotted from outside — screen capture filters to
applications it has been granted, and an `LSUIElement` app running from a
build directory cannot be granted. The trace is the only way to see inside it,
which is why it exists.

Whatever this finds is fixed before phase 2. A first release whose main
feature does not work is not recoverable by a second one.

## Phase 2 — Cut 0.7.0

**Exit: `Hoot.dmg` opens on a Mac that has never seen this project, with no
Gatekeeper warning, and the shelf works on it.**

Bump `CFBundleShortVersionString` in `Packaging/Info.plist`. 0.6.0 shipped on
12 September with renaming and without the notch; everything since — the
shelf, tabs, the folder tree, click pairing — is unreleased.

    SIGN_IDENTITY="Developer ID Application: … (TEAMID)" \
    NOTARY_PROFILE=hoot-notary ./Packaging/release.sh

Then verify it somewhere that is not this machine. A second Mac, or a fresh
user account on this one — the point is a machine where the app has never
been run and no security-scoped bookmark exists, because first launch is the
one path that cannot be tested from a developer's own account. Check that the
folder picker appears, that the grant survives a restart, and that the notch
panel comes up on a notched display.

**A decision to make here: arm64 or universal.** The build is Apple silicon
only and the page says so, honestly. macOS 13 runs on Intel Macs, so an
Intel build would widen the audience — but no Intel Mac has a camera housing,
so the shelf would be absent on every one of them, and the page would need to
say which features you get. Staying arm64-only keeps one product with one
description. That is the recommendation, and it is reversible.

## Phase 3 — The page

**Exit: every sentence on the page is true of the build the Download button
hands out.**

`Website/README.md` is the brief, written from what the app actually does.
The page is two releases behind and one claim becomes false the moment the
shelf ships.

- **The one-folder promise.** "macOS grants access to that folder alone" is
  true today and false on release day. The replacement wording is in
  `docs/privacy.md`: one folder organized, any number read, never written —
  and *say that the entitlements did not change*, or a promise that grew
  reads as one being walked back.
- **Version and links.** 0.5.0 in two places, four links pinned to `v0.5.0`.
  Point them at `releases/latest/download/Hoot.dmg` so they cannot rot again.
- **Renaming, and sorting by type.** Neither word appears on the page. The
  second has the stronger privacy story of the two modes and the privacy
  section does not know it exists.
- **The notch shelf**, once phase 2 has actually shipped it.
- **Delete the unsigned-build warning.** It stops being true in phase 2, and
  a scary warning left on a page for a build that no longer scares anyone
  costs downloads.
- **Mobile.** ~9pt of horizontal overflow at 375px. Measured earlier; worth
  re-measuring rather than trusting.

`Main.dc.html` and `Phone.dc.html` carry the same claims verbatim, so a page
regenerated from them puts the wrong ones back. Fix them in the same pass, not
afterwards.

## Phase 4 — Publish

**Exit: the tag exists, the DMG is attached to it, and the page's Download
button downloads that file.**

Release notes are the thing that is easy to skip and hard to add later. The
commit messages in this project are already written as explanations; the notes
are those, shortened, in the order somebody who has never seen the app would
want them. Lead with what is new, not with what was fixed.

Say plainly in the notes that there is no automatic update — see below — so
that the first thing a user learns about updates is not that they missed one.

## Phase 5 — The consequences of the privacy claim

**Exit: these three are decided and written down, before somebody finds them
the hard way.**

The app has no network entitlement. That is the best sentence on the site and
it is not free:

- **No update check.** Sparkle and every other updater needs the network.
  There is no way to tell a user a new version exists. The honest answer is to
  say so on the page and in the notes, and to treat the release page as the
  place people come back to. Adding a network entitlement "just for updates"
  trades the strongest claim in the product for a convenience.
- **No crash reports, no analytics.** Nothing tells you an install is broken.
  Bug reports arrive as GitHub issues or not at all, and the page already
  links to them.
- **No telemetry means no numbers.** Download counts on the release are all
  you will have. Decide now that this is acceptable, because the alternative
  is the same trade as above.

## Not in scope

**Paid distribution.** Considered and dropped. The repository is public and
MIT-licensed, so anyone may build and use Hoot free, permanently — and
`docs/privacy.md` uses exactly that as its evidence: "The source is there to
check." Selling downloads would have meant either closing the source, which
takes away the proof behind the privacy page, or gating a file that anybody
can already produce from the repository. Neither is worth it.

MIT is also irrevocable for what is already published, so this is a decision
about the future only.
