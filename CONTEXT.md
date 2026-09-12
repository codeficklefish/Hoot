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
