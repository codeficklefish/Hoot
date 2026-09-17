# 0003 — Many folders read, one folder written

**Status:** accepted, 17 September 2026.

## What was decided

The notch shows a *shelf*: the contents of any number of folders the user
picks. Hoot still organizes exactly one folder, and the shelf never writes to
anything.

## Why the notch changed at all

The HUD's first version walked the plan one folder at a time — the files
going into a folder, why they belonged together, and a Move-or-Leave
decision. That is the review window's job, done again in a smaller space. Its
other tab counted what was waiting, which is the menu bar popover's job, done
again. Two surfaces, both duplicates.

It was also conditional on there being something to file. `HUDController`
hid the panel unless a non-idle walk existed, so on a folder that was already
tidy there was nothing at the notch to point at, and hovering the camera
housing did nothing whatsoever. That read as a bug and was reported as one.
It was this design showing through.

A shelf answers the question the other two surfaces do not: *what is in that
folder.* It is worth opening whether or not anything needs filing.

## Why the shelf may have several folders when the organizer may not

Because it cannot write.

Every safety rule in `docs/coding-standards.md` is about writing — nothing is
deleted, nothing moves without approval, every move is reversible, nothing is
written outside the watched folder. A surface with no verb that writes adds
no new way for any of them to fail. That is what buys the second, plural
grant, and it is the only thing that buys it.

Keeping the *organizer* single-rooted matters for reasons that are load-
bearing rather than tidy:

- `Organizer.verifyContained(_:within:)` is safety rule 4, and it is one root
  by construction. Multi-root turns one containment predicate into "contained
  in any of N roots", which is a strictly weaker guarantee and a harder one
  to read.
- Undo compares `operation.source.deletingLastPathComponent()` against the
  watched folder. A second root breaks that comparison silently.
- `WaitingAnnouncer` owns exactly one "count last announced", consolidated
  there deliberately after being spread across three files.
- `LearnedClassifier` and `ExistingFolders` are built from the watched
  folder's own subfolders. Two roots means two taxonomies, or one taxonomy
  pretending two folders are one filing system.

## The sandbox did not have to change

`com.apple.security.files.user-selected.read-write` and
`com.apple.security.files.bookmarks.app-scope` already mean "whatever the
user picks, however many times". No entitlement was added, and none was
needed. What changed was Hoot's own structure: `FolderAccessing` kept its
singular shape for the watched folder, and `FolderSetAccessing` was added
beside it rather than generalising it — widening the first would have made
every caller ask "which folder?" about a question with exactly one answer,
and quietly invited a second root into the containment rule.

## What this costs

The privacy page can no longer say "one folder — Hoot has no access to
anything else on your Mac", which was a good sentence and true. It now has to
say two things instead of one: one folder organized, any number read, and
never written. That is more words for the same guarantee, and the guarantee
is the one that was load-bearing.

## What was considered and rejected

**Keeping the tidy walk as a third tab.** It would have left the duplication
that motivated the change.

**Making the organizer multi-root.** It would have touched
`OrganizationPlan`, `Organizer`, undo, learning and the announcer, and
weakened safety rule 4, in order to avoid adding one protocol.

**Listing no sub-folders.** Considered, because a shelf that lists folders
invites navigating into them, which is a file browser rather than a shelf.
The design lists them, sorted first as the Finder does, and they are not
navigable — a folder row reveals in the Finder rather than descending. That
is one line to reverse if it proves wrong.
