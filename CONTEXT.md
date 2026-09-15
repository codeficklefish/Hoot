# Domain language

The words Hoot's code uses, and what they mean here specifically. Use these
names in code, comments and commits; where a term has a narrower meaning than
its everyday one, the narrowing is the point.

This file is grown as terms are settled rather than written all at once, so it
is deliberately short. Absence from it means a term has not been pinned down
yet, not that it is unimportant.

## The watched folder

**Watched folder** — the single directory Hoot has been pointed at. There is
never more than one. Everything Hoot does happens inside it, and safety rule 4
is that nothing is ever written outside it, checked after symlinks are resolved.

**Grant** — the user's permission to read and write the watched folder, and the
durable record of it. On macOS the grant is a security-scoped bookmark, because
the sandbox otherwise forgets the folder when the app quits; on Windows a stored
path would be enough. `FolderAccessing` is the seam: the engine knows a folder
can be remembered, asked for again and given back, and nothing more.

Restoring a grant is not free and not silent — it opens an operating-system
resource and starts a watcher — so it happens in `AppState.start()`, never as a
side effect of constructing something.

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

A rename is not a new kind of operation. It is a move whose destination
folder is the folder the file is already in, which is why history records it
and undo reverses it without either knowing renaming exists.

## The HUD

**The HUD** — a bar that grows out of the camera housing on a notched
display. At rest it is the size of the cutout, so on the hardware it is meant
for it is *invisible*; pointing at it opens the panel. Hover rather than a
click, because there is no affordance to aim at when the thing at rest cannot
be seen — aiming at the housing has to be enough.

**A tidy walk** — the HUD's unit of work: one folder at a time, shown with
the files going into it and the reason they belong together. Answered with
**Move & name**, or **Leave**, and then the next one. `TidyFlow` owns the
walk — which group is up, which files are still ticked, and the tallies the
closing summary is built from.

**Paging** — moving between folders without answering any of them, by swipe,
by clicking a pip, or with ⌃⌥←/→. The distinction is the point: a folder you
paged past is still owed an answer, so the walk comes back round for it and
is over only when every folder has been answered. `TidyFlow` keeps a set of
the answered ones rather than a high-water mark for exactly this reason.

**The tray** — the HUD's other tab, answering "how much is waiting" rather
than "should this folder happen". Tiles rather than rows, because a quantity
is read at a glance where filenames have to be read one at a time.

Both decisions are on screen together — where a file goes and what it is
called — because they are answered together. A file whose name says nothing
is usually also one you cannot place by looking at it, so splitting them
would mean asking about the same file twice on two different screens.
**Rename** is the one setting that lives beside the decision rather than in
Settings, because it changes what the button in front of you will do.

**Left alone** — the files a plan decided not to touch. Named once, in
`OrganizationPlan`, because three surfaces show that count and they have to
agree on the word as well as the number.

All three surfaces read the same plan, and that is a rule rather than a
coincidence. They used to disagree: the popover counted every file it had
found and labelled each with the classifier's category, so a file the plan
had decided to leave alone still appeared under a destination, as though it
were about to move. The counts that remain different — ten in the folder,
seven proposed to move — are now the plan's own arithmetic, and each surface
says which it means.
