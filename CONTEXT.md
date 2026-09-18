# Domain language

The words Hoot's code uses, and what they mean here specifically. Use these
names in code, comments and commits; where a term has a narrower meaning than
its everyday one, the narrowing is the point.

This file is grown as terms are settled rather than written all at once, so it
is deliberately short. Absence from it means a term has not been pinned down
yet, not that it is unimportant.

## The watched folder

**Watched folder** — the single directory Hoot *organizes*. There is never
more than one, and safety rule 4 depends on that: nothing is ever written
outside it, checked after symlinks are resolved. Everything Hoot *does* to a
file happens here.

Not to be confused with the folders on the shelf, which Hoot only reads. The
distinction is load-bearing rather than tidy — see
[decision 0003](docs/decisions/0003-many-folders-read-one-folder-written.md).

**Grant** — the user's permission to read and write the watched folder, and the
durable record of it. On macOS the grant is a security-scoped bookmark, because
the sandbox otherwise forgets the folder when the app quits; on Windows a stored
path would be enough. `FolderAccessing` is the seam: the engine knows a folder
can be remembered, asked for again and given back, and nothing more.

Restoring a grant is not free and not silent — it opens an operating-system
resource and starts a watcher — so it happens in `AppState.start()`, never as a
side effect of constructing something. That is now true several times over:
the shelf restores one grant per folder there.

`FolderAccessing` is the watched folder's grant and stays singular;
`FolderSetAccessing` is the shelf's and is plural. Two seams rather than one
keyed seam, because widening the first would make every caller ask "which
folder?" about a question that has exactly one answer.

**The same folder** — two URLs naming one folder very often do not compare
equal. A security-scoped bookmark resolves to the canonical path with a
trailing slash where the URL it was made from had neither. `FolderIdentity`
is the one answer to that, and comparing without it made adding a shelf
folder twice give it two tabs and made forgetting one do nothing at all.

## Speaking up

**Pile** — the files currently waiting for review in the watched folder.

**Quiet period** — how long the folder must stop changing before Hoot says
anything. Extracting an archive can produce dozens of files in a second, and the
quiet period is what turns those into one notification instead of dozens.

**Announcement** — what Hoot has decided to say about a pile, unprompted. Only
growth is announced: a pile that shrank because the user organized some of it,
or that held steady, is not news. Nor is the opening sweep of a folder Hoot has
just been given — the user put those files there themselves.

`WaitingAnnouncer` owns all of this, including the count last announced. That
count was previously a field on the app's state written from three different
files, which is how a rule like "don't say the same thing twice" stops holding.

## Confidence

**Confidence** — how much an answer about a file is trusted, on 0...1. Built
from *agreement between independent sources*, never from a source's own opinion
of itself: the on-device model reports 95–100% for everything, including wrong
answers, so its self-scored number is discarded entirely. Below
`lowConfidenceThreshold` Hoot leaves the file alone rather than guessing.

**Signal** — one piece of evidence contributing to confidence, with the weight
it carries alone. Signals combine with a noisy-OR rule, so two sources that
could each fail independently are much stronger than one source repeated.

**Source** — where a signal was read: the filename, the text inside, the file
type, the provider, the project, the user's own filing. Confidence takes *one
weight per source*, not one per signal. Noisy-OR is only honest about things
that can fail separately, and four keywords read out of one filename cannot —
a misleading name is misleading in all of its words at once. Repetition within
a source raises it slightly and is capped well short of certainty. Counting
each keyword as its own chance took `invoice-template-blank.pdf` to 0.95 on
the strength of a name that says the opposite.

**Strength** — the exception, and the only signal that carries its own weight.
It is the margin by which the personal model's winning folder beat the runner-up,
measured from the user's own filing. Not a self-assessment: a folder that barely
won genuinely is worth less than one that won outright, and spending the margin
rather than replacing it with a constant is what says so.

## Names

**A name that says nothing** — a filename carrying no information about the
file: a camera number, a row of digits, a keyboard mash, a hexadecimal blob,
or nothing but the words that mean "I did not name this". `MeaninglessName`
decides this, and it is deliberately reluctant: it answers "is this certainly
noise?", never "could this be better?". `CV.pdf` says something. Renaming a
file the user named themselves is worse than leaving a hundred camera numbers
alone.

**Proposed name** — a name Hoot would like to give a file, carried with the
reason it was chosen. The reason is not decoration: a proposed name is a
claim about a file the user cannot see from where they are being asked, and
the sentence saying which words it came from is the difference between a
decision and a coin toss.

A name may only come from text **genuinely read out of the file**. Not from
the old filename, which is the thing that failed, and not from a guess about
a picture — `ExtractedEvidence.isTextual` is what separates words on a
photographed receipt from "appears to show: outdoor, sky, water".

**Grounded** — a proposed name every word and every long number of which can
be found in the excerpt the model was shown. `NameGrounding` decides this, and
it is the only thing that enforces "invent nothing": that rule lives in the
prompt, and a prompt is a request. Everything else checked about a proposed
name guards the *path* — that it cannot traverse, hide a file or swap an
extension. Grounding guards the *claim*, which is what the user will later go
looking for the file by.

It is checked against the text that was actually sent, never a fresh read: a
name honestly derived from what the model saw must not fail because the file
was read differently the second time.

A rename is not a new kind of operation. It is a move whose destination
folder is the folder the file is already in, which is why history records it
and undo reverses it without either knowing renaming exists.

## The HUD

**The HUD** — a bar that grows out of the camera housing on a notched
display. At rest it is the size of the cutout, so on the hardware it is meant
for it is *invisible*; pointing at it opens the panel. Hover rather than a
click, because there is no affordance to aim at when the thing at rest cannot
be seen — aiming at the housing has to be enough.

**Root and listing** — a shelf tab has two URLs. `ShelfFolder.root` is the
folder that was added and the one the sandbox granted; `url` is the directory
on screen, which is the root or somewhere under it. Identity, the tab's name
and the bookmark all follow the root, so going three folders down does not
rename a tab or lose its place. `parent` is the way back up and returns nil at
the root — the containment rule for climbing, in the engine where it is
checked, for the same reason `Organizer.verifyContained` is.

**Open in place** — a folder row's triangle, and what space does to one:
its contents are spliced into the list beneath it, indented, and the list is
otherwise untouched. `FileShelf.open` holds which folders are open and
`rows` flattens the tree into `ShelfRowItem`s carrying a depth. Capped at
`maxDepth`, because indentation costs width out of a 420pt panel.

Two earlier shapes were wrong the same way: space *navigated*, and then space
laid a card *over* the list. Both took away the thing being looked at in
order to answer a question asked while looking at it.

**Key** — `ShelfEntry.key`, the canonical spelling of a row's path, resolved
once by the reader. Open folders are keyed on it, not on the path as written:
the reader hands back `/private/var/…` where a path built by hand says
`/var/…`, and closing a folder under one spelling left it open under the
other. Same rule as `FolderIdentity`, same reason, third place it has bitten.

**Going in** — double-click on a folder row lists it in the panel.
It is still a read, which is the whole reason it is allowed: see decision
0003, which ruled the other way first and records why that was wrong. Escape
puts down the picked row, and then climbs a level.

**The shelf** — what the HUD shows: the contents of folders the user picked,
one folder at a time, as a list. `FileShelf` owns which folders there are,
which is showing, the order they are read in and which row is picked;
`ShelfReader` turns one folder into rows.

The shelf **reads and never writes**. That sentence is the whole reason it
may hold several folders while the organizer holds one, because every safety
rule in this project is about writing. If anything here ever moves, renames
or deletes a file, that reasoning is gone.

It replaced a *tidy walk* — one folder at a time with a Move-or-Leave
decision — which was the review window's job done again in a smaller space,
and a *tray* counting what was waiting, which was the popover's. The walk was
also conditional on there being something to file, so a tidy folder left
nothing at the notch to point at.

**Paging** — moving between shelf folders, by swipe, by pointing at a tab or
clicking one, or with ⌃⌥←/→. It no longer leaves anything owed: a folder is a
thing to look at, not a question to answer, so there is nothing to come back
round for. The tab row scrolls to follow the selection rather than being
scrolled by hand, because the horizontal gesture over the panel is already
paging — and it holds still while the pointer is on it, or a tab moving under
the cursor would be read as the next hover.

**Dwell** — how long the pointer has to stay on a tab before it counts as
pointing at it rather than crossing it. `FileShelf.hoverDwell`. The row is
also the way to the `+`, so every trip to that control passes over every tab;
without the wait, one reach would change folder three times. `shouldShow` is
the other half: the tab already showing answers no, so a cursor crossing its
own tab neither re-reads the folder nor puts down the picked row.

**Focus** — the panel takes keyboard focus when a row is *clicked*, and never
when it is merely pointed at. The distinction is the whole of it: hovering
must stay free, or the HUD cannot be opened mid-sentence, while a spacebar
can only reach a window that is key. The alternatives were a global monitor,
which can see the key but not consume it and would type a space into whatever
was frontmost as well as previewing, and a system-wide hot key, which would
take the spacebar away from every app on the Mac.

**Tidy N** — the organizer's one appearance at the notch, and a door rather
than a verb: it opens the review window. It can only ever show on the watched
folder, because that is the only folder there is a plan for — the
read-many-write-one rule showing through the interface instead of being
asserted in a comment.

**Left alone** — the files a plan decided not to touch. Named once, in
`OrganizationPlan`, because the surfaces that show that count have to agree
on the word as well as the number.

Every surface that describes the plan reads the same plan, and that is a rule
rather than a coincidence. They used to disagree: the popover counted every
file it had found and labelled each with the classifier's category, so a file
the plan had decided to leave alone still appeared under a destination, as
though it were about to move. The counts that remain different — ten in the
folder, seven proposed to move — are the plan's own arithmetic, and each
surface says which it means.

The shelf is the exemption, and it is exempt for a reason rather than by
oversight: it is not describing the plan at all. It says what is in a folder,
which is a fact about the disk, so it cannot disagree with a plan it never
consults. The one number it takes from the plan is `Tidy N`, and that comes
from the plan directly.
