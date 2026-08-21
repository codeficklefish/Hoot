# Coding standards

Conventions this project follows, adapted from the ONETT project's. These
complement — not replace — the rules in [`architecture.md`](architecture.md).

## File size & modularity

- **Aim to keep source files under ~300 lines.**
- Split by **single responsibility**, not merely by line count. `AppState` was
  split because watching a folder, planning a move and remembering a correction
  are three jobs — not because it was long.
- **No "god files"** and no misc/util dumps. Every file has a nameable job.
- If a file deliberately exceeds ~300 lines, say why in the file.

## General

- **SOLID / DRY / KISS**; small, single-purpose functions.
- **Validate untrusted input at the boundary.** A language model's output is
  untrusted input: it is sanitized in `SuggestionValidator` before it can
  become a folder name, never deeper in.
- **Errors are explicit and typed.** Fail loudly rather than compute something
  silently wrong — an unsupported case raises rather than guessing.
- **Say what the code cannot.** Comments explain *why* a choice was made,
  especially where the obvious approach was wrong. Bugs found the hard way are
  recorded next to the fix.
- **Remove dead code as you go.** `FileItem.contentType` was carried for months,
  used nowhere, and blocked a Windows build on its own.

## Safety rules that are not negotiable

These are properties of the product, not preferences:

1. Nothing is deleted, ever.
2. Nothing is moved without the user approving it.
3. Every move is reversible.
4. Nothing is written outside the watched folder — checked after symlinks are
   resolved, not before.
5. A file whose contents live in the cloud is never opened.

Each has a test. Changing one means changing the test deliberately.

## Gates (must pass before a commit is recommended)

| Area | Command |
|---|---|
| Build | `swift build` |
| Dependency rule | `swift test` |
| Behaviour & safety | `./Verification/run.sh` |
| Accuracy (when folders exist) | `./Evaluation/run.sh` |
