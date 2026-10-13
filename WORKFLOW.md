# OITUI Git workflow

## Branches

- **`main`**: tested, release-ready code only. Nothing is committed to it directly.
- **`experiments`**: the single working branch. All unfinished OITI/OITS work, experiments, temporary diagnostic code and unstable changes live here until they have run on the device.

There is never more than `main` plus one working branch.

## Landing work

1. Develop and test on `experiments`. Mark untested work as untested in the commit message or the file header.
2. When a set of changes has been tested on-device, open a pull request `experiments` -> `main`.
3. Review the diff, then **squash merge**. One squash commit per PR keeps `main` linear and readable. Do not use merge commits.
4. After the merge, GitHub deletes the finished `experiments` branch automatically. Create a fresh one from the updated `main`:

   ```
   git fetch --prune origin
   git switch main
   git pull --ff-only
   git branch -D experiments
   git switch -c experiments
   git push -u origin experiments
   git rev-parse main experiments origin/experiments
   ```

   The three hashes must match. `-D` is needed because a squash merge does not make the old branch an ancestor of `main`, so `-d` refuses. Check the PR shows as merged before deleting. If git says the local branch does not exist, ignore that line.

**Test before merging.** Do not open the PR until the changes have run on the phone. Minimum check: stock settings still look stock (every Island setting at its default), banners, the settings pages touched by the change, and the respring-loop guard (`COMMANDS.md`, section 7).

Never force-push `main` or rewrite its history.

## Releases

A commit on `main` is not automatically a release. A release is a version tag plus a GitHub Release with the packages attached. Only `main`, only tested work.

- **Build on the Mac** (not the Arch PC: its arm64e objects warn about an incompatible ABI) with `FINALPACKAGE=1`, after clearing the old `packages/` folders. Ship **OITCore and OITI together** (OITI depends on OITCore). Do not ship OITS until it is verified.
- **Versions** live in each module's `control` file (`Version:`). Keep them ascending: dpkg sorts `0.0.10` below `0.1.0`. Bump the version through a normal PR before tagging. Tag names are `vMAJOR.MINOR.PATCH`.
- **Test the exact `.deb` files** on the phone (`scp`, `dpkg -i`, `sbreload`) before publishing.
- Exact commands: `COMMANDS.md`, section 10 ("Releases"). Released so far: `v0.1.0` (`46cf122`).

## Logging policy

- Release defaults are quiet: `DiagnosticsLevel` defaults to 0 in OITI, OITS and `OITLogger`. Warnings and errors that matter in normal use (safe mode, self-check, MobileGestalt writes, main-thread stalls) are written at level 0.
- Verbose or per-call logging, dumps, polling timers and system-notification taps run only when `DiagnosticsLevel` is raised with `defaults write`. See `DIAGNOSTICS.md`.
- Do not delete useful diagnostics to tidy the code; gate them behind the level instead.
