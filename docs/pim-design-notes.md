# Hoot and the science of personal information management

Design notes on applying Bergman & Whittaker, *The Science of Managing Our
Digital Stuff* (MIT Press, 2016), to Hoot.

## The tension this book creates for Hoot

The book's central empirical claim is uncomfortable for an automatic file
organizer: **active self-organization builds the memory that later enables
retrieval.** Organizing is not just a cost to be eliminated — the act of
filing is itself what makes a file findable later.

Two findings make the point sharply:

- Retrieving from folders **someone else** organized failed **28%** of the
  time, against **5%** for self-organized folders (ch. 7).
- The authors' Conclusions name automatic classification directly: it "risks
  removing the active organization that itself aids memory," and "full
  automatic organization has never been successfully deployed at scale."

To Hoot's user, an AI is "someone else." So the goal is not to organize *for*
the user, but to lower the cost of the user organizing — keeping their
judgement, vocabulary and attention in the loop where it matters.

## What the research endorses in Hoot's existing design

| Finding | Where Hoot already agrees |
|---|---|
| People think in **projects**, not formats; format-based hierarchies cause "project fragmentation" (ch. 11) | Grouping is semantic, and the spec's rule "do NOT organize purely by extension" is enforced |
| **Navigation beats search** for personal files — 56–68% navigation vs 7–15% search, biologically grounded (ch. 5, 8) | Hoot builds folder hierarchies to navigate rather than relying on Spotlight |
| **Folders beat tags** — 96% of files in specific folders, only 16% of users tagged anything (ch. 6) | Single-classification folders, no tagging layer |
| PIM is **communication with one's future self** using subjective, personal cues (ch. 9) | Learned folder renames: Hoot converges on the user's vocabulary, not the model's |

## What the research changed

### 1. Folder shape now follows the measured depth/size trade-off

Bergman et al. (2010, N=296) timed real users navigating their own files:
each extra folder level costs roughly the same time as scanning **~21 extra
items**. Depth is not free.

Hoot previously split *every* project into `Documents/`, `Data/`, `Images/`.
For a three-file trip folder that bought nothing and cost a level — and it
quietly reintroduced the format-based fragmentation that project grouping
exists to remove.

Now role subfolders appear only once a project exceeds ~21 files, where the
split genuinely saves more scanning than the extra level costs.
(`OrganizationPlanner.subfolderWorthwhileThreshold`)

### 2. Demotion instead of deletion

Chapter 10's "deletion paradox": unimportant files clutter the view, but
deciding whether to delete is itself effortful and risky, so people
overkeep — only ~17% of photos and 22% of paper are ever discarded.
Demotion sidesteps the decision: reduce visibility, keep the file.

Their `Old'nGray` prototype grayed out superseded versions and cut retrieval
failures from **24% to 4%**, roughly halving retrieval time.

Hoot has a particular obligation here: its own collision-safe naming
*manufactures* version clutter (`report.pdf`, `report 2.pdf`). So
`VersionFamilies` detects version families and routes superseded copies to a
`Previous Versions/` subfolder — visible, adjacent, never deleted. The review
screen shows them dimmed and labelled "older version".

This also keeps implementation rule #1 intact: Hoot never deletes anything.

### 3. Nothing joins a project without evidence

The first attempt at this was wrong, and worth recording.

Reasoning from the 28%-vs-5% finding, Hoot began leaving weakly-evidenced
moves **unticked** so the user had to approve them deliberately. In testing
that proved to be friction in the wrong place: it unticked every ordinary
image and archive — most of a Downloads folder — while doing nothing about
the actual failure, which was files being grouped *wrongly* in the first
place. Real example: four images with meaningless names
(`images.jpg`, `301847592_…n.jpg`, `sh-unsplash_…jpeg`, `hoot-owl-icon.png`)
were swept into invented "Software Development" and "AI" projects.

The mechanism was removed. Asking the user to tick a box does not fix a bad
suggestion; it just makes them complicit in it.

What replaced it addresses the cause. A model asked to group *will* group, so
membership now requires evidence, checked in `SuggestionValidator`:

- the provider actually read text from inside the file, **or**
- its filename shares a distinctive word with the project name or another
  member — the same signal rule-based grouping uses.

Images are the common casualty, and correctly so: there is no OCR, so a
camera-roll photo carries no evidence at all. Filing it under its type is
honest; filing it under a guessed project buries it in exactly the
someone-else's-scheme folder that fails 28% of the time. If stripping
unsupported files leaves fewer than two members, the project is discarded
entirely.

Every proposed move is pre-approved again. Hoot's job is to make a suggestion
worth accepting, not to hedge a weak one.

## Deliberately not adopted

- **Tags / multiple classification** (ch. 6): measured worse in personal use;
  users found multiple tagging redundant and effortful.
- **Search-first design** (ch. 5): better search engines did not durably shift
  users away from navigation; the preference is cognitive, not technological.
- **Group/shared repositories** (ch. 7): out of scope, and the failure mode
  (reverse-engineering another person's scheme) is the same one Hoot must
  avoid being the cause of.

## Open ideas from the book, not yet built

- **Subjective context** (ch. 12): `ItemHistory` logged which files were open
  together. Hoot's nearest equivalent would be treating co-arrival in the
  watched folder as evidence of a shared project — currently declined as too
  noisy for a Downloads folder, but the book's temporal-context argument is a
  reason to revisit it with better signals.
- **Promotion** (ch. 10): Hoot demotes but does not yet promote. Recency and
  frequency biases in retrieval (ch. 4) suggest surfacing recently-used items.
- **Multi-device PIM**: named as a growing challenge; Hoot is single-Mac.

## Calibrating confidence against real files

The request was to fit the confidence weights to the user's own files. The
attempt is worth recording, because what it found was more useful than a
fitted weight would have been.

**Ground truth.** Twelve files the user had already sorted into folders of
their own (`Books`, `Finance`, `Food`, `Icons`, `Nature`, `Photography`,
`School`, `Software`, `Software Development & AI`). Where they put a file is,
by definition, the right answer.

**First finding: the measurement was noise.** Running the *same* code over the
*same* files five times gave accuracies of 41%, 58%, 58%, 66% and 33% — a
33-point spread, with one photo landing in "Nature" on one run and
"Photography" on the next. Fitting weights to any single run would have been
fitting a coin toss.

**Cause: the model was sampling randomly.** `FoundationModels` defaults to
random sampling. For open-ended generation that is reasonable; for filing
decisions it is actively harmful — a user cannot form a mental model of a tool
that answers differently each time. Switching to `GenerationOptions(sampling:
.greedy)` made runs identical (58%, 58%, 58%).

**Second finding: with the noise gone, measurement paid off immediately.**
Two real defects surfaced that had been invisible:

- Scene labels were drowning out text read from images. Naming example
  categories in the prompt then caused the model to reuse them verbatim —
  the same few-shot leakage seen earlier with project names — so the guidance
  had to stay abstract.
- The provider was allowed to overturn a better-supported answer with a
  worse-supported one, which turned a correctly-filed `Finance` document into
  `Software`. Fixing that naively broke a different case, because two kinds of
  claim were being compared as if equivalent: "Images" asserts what a file
  *is*, "Photography" asserts what it is *about*. A subject claim may now
  replace a type claim even at lower confidence; it must out-evidence another
  subject claim.

Accuracy went 58% → 66%.

**Third finding: no reweighting was justified.** Stated confidence averaged
64% against 66% actual accuracy — a gap of −2 points, i.e. very slightly
*under*-confident. There is nothing to correct, and with n=12 any adjustment
would be indistinguishable from noise.

**What remains wrong** is mostly not error but taxonomy: three books filed as
`Books` belong, in this user's scheme, under `Software Development & AI`. Hoot
has no way to know that a user splits their books by subject until they say
so — which is what the learned-rename mechanism exists for.

`Evaluation/run.sh` re-runs this measurement. It becomes more meaningful as
more folders are curated; at a few dozen files per category, fitting the
weights properly would be worth revisiting.
