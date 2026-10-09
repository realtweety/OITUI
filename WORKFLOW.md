# OITUI Git workflow

## Branches

- **`main`**: tested, release-ready code only. Nothing is committed to it directly.
- **`experiments`**: the single working branch. All unfinished OITI/OITS work, experiments, temporary diagnostic code and unstable changes live here until they have run on the device.

There is never more than `main` plus one working branch.

## Landing work

1. Develop and test on `experiments`. Mark untested work as untested in the commit message or the file header.
2. When a set of changes has been tested on-device, open a pull request `experiments` -> `main`.
3. Review the diff, then **squash merge**. One squash commit per PR keeps `main` linear and readable. Do not use merge commits.
4. After the merge, delete the finished `experiments` branch (on GitHub and locally) and create a fresh one from the updated `main`:

   ```
   git switch main
   git pull --ff-only
   git branch -D experiments
   git switch -c experiments
   git push -u origin experiments
   ```

   `-D` is needed because a squash merge does not make the old branch an ancestor of `main`, so `-d` refuses. Check the PR shows as merged before deleting.

Never force-push `main` or rewrite its history.

## Releases

A commit on `main` is not automatically a release. A release is a version tag plus a GitHub Release:

```
git tag -a v0.1.0 -m "OITUI 0.1.0"
git push origin v0.1.0
gh release create v0.1.0 --title "OITUI 0.1.0" --notes "..." packages/*.deb
```

Use `vMAJOR.MINOR.PATCH`, tag only commits on `main` that have been tested on-device, and attach the built `.deb` files.

## Logging policy

- Release defaults are quiet: `DiagnosticsLevel` defaults to 0 in OITI, OITS and `OITLogger`. Warnings and errors that matter in normal use (safe mode, self-check, MobileGestalt writes, main-thread stalls) are written at level 0.
- Verbose or per-call logging, dumps, polling timers and system-notification taps run only when `DiagnosticsLevel` is raised with `defaults write`. See `DIAGNOSTICS.md`.
- Do not delete useful diagnostics to tidy the code; gate them behind the level instead.
