# OITUI: Claude Code Project Instructions

## Mission

OITUI (Order In The User Interface) is a modular jailbreak-tweak project that brings modern iOS interface features to older devices. Work carefully: SpringBoard hooks and status-bar view handling can cause device-wide regressions.

Treat this file as project guidance, not a substitute for inspecting the current code. Keep this file concise and update it when a lasting project convention changes.

## Start Every Task Safely

1. Confirm the repository root and current branch. Inspect `git status --short --branch` and recent commits before editing.
2. Preserve all pre-existing and uncommitted work. Do not assume every change in the working tree belongs to the current task.
3. Read the relevant source, Makefiles, package metadata, and documentation before proposing or changing behavior.
4. For non-trivial work, read `OITUI_HISTORY.md`, especially the relevant hard-won technical lessons and debugging history. Read `README.md` and other relevant docs as needed.
5. Treat history and documentation as potentially stale. Check claims against the current source, recent commits, and the user's latest instructions. Do not repeat a known-bad approach simply because an older document mentions it.
6. Before a substantial implementation, briefly state the plan and the files likely to change. Ask a question only when a missing detail blocks safe progress.

## Project Context

- The repository contains separate components such as OITI, OITS, and OITCore, plus diagnostic tooling. Verify the current layout rather than assuming every historical component is still active.
- OITI implements Dynamic Island-related behavior and has included notification-related features. OITS customizes status-bar elements. OITCore provides shared utilities. Inspect current code before relying on these summaries.
- The project targets jailbroken iOS, with iOS 16 and rootless Theos packaging important to compatibility. Confirm the current target and package settings in the relevant Makefiles and control files.
- The iPhone 8 Plus on Dopamine/rootless iOS 16 has been a key test environment, but do not assume a device is connected or available for testing.
- OITG is not active scope unless the user explicitly asks to work on it. Do not introduce or revive it as part of unrelated work.

## Implementation Standards

- Prefer the smallest correct change that fits the existing architecture. Avoid broad refactors, unrelated cleanup, and speculative rewrites.
- Search for existing helpers and call sites before adding new utilities or changing shared behavior.
- Preserve existing behavior outside the requested scope. Check callers, lifecycle assumptions, ownership, and cleanup when changing hooks, observers, callbacks, or view traversal.
- Respect iOS-target and rootless packaging requirements. Do not change deployment targets, package identifiers, dependencies, or project structure without a clear reason and explicit discussion when the change is consequential.
- Avoid hardcoding machine-specific paths, device IP addresses, credentials, or local environment assumptions. Reuse established project configuration when possible.
- Add comments to explain non-obvious reasoning, constraints, and workarounds, not to restate what the code already says.
- Never invent APIs, test results, compiler output, or device behavior. Clearly label anything that remains unverified.

## Build and Test

- Inspect the relevant Makefile and available targets before running build commands; run commands from the correct component directory.
- Prefer build/package-only validation such as the project's supported `make package` target when available. Report the exact command used and whether it succeeded.
- Do not run `make install`, `make package install`, deploy a package to a phone, respring a device, or change device settings unless the user explicitly requests that action in the current conversation.
- Do not assume Theos, SDKs, a signing setup, or a test device is available. If validation cannot run, explain the specific limitation and perform appropriate static checks instead.
- After edits, inspect the final diff and check for accidental unrelated changes. Summarize what changed, what was tested, and any remaining risks.

## Git and Branch Safety

- `main` is the stable branch. `experiments` is the development branch.
- Do not merge `experiments` into `main` unless the user and assistant have reviewed the intended changes and the user explicitly approves the merge.
- Prefer feature branches based on `experiments` for new development unless the user specifies another base. Verify the actual branch and target before acting; do not switch branches automatically.
- Never force-push, rewrite shared history, or run destructive operations such as `git reset --hard` or `git clean -fd` without explicit approval.
- Do not discard, overwrite, or silently stash the user's work. Do not stage everything with `git add -A`; stage only files that belong to the requested change.
- Do not commit or push unless the user requests that action. Before committing, inspect both the working diff and staged diff.

## GitHub Actions and Collaboration

- Use `gh` only after confirming the repository and relevant authentication/status when needed. Never expose tokens or other credentials.
- For issue comments, PR conversation comments, inline review comments, reviews, branch pushes, PR creation/retargeting, issue closure, and releases, show the intended action and exact public text first unless the user explicitly requested that specific action in the current conversation.
- Draft PR descriptions from the real diff and actual validation results. Clearly state untested areas; do not claim checks passed unless they were run and passed.
- Never merge a PR or publish a release without explicit approval. Never approve a PR on the user's behalf unless explicitly instructed.
- When reviewing a PR, prioritize concrete correctness, regression, compatibility, and lifecycle issues. Report findings by severity with file/line references where possible; do not invent issues to fill a report.

## Communication

- Be direct and stepwise. For terminal troubleshooting, lead with one main action at a time and explain risky commands before running them.
- Separate confirmed facts from hypotheses. If a build, device test, or GitHub action did not run, say so plainly.
- Do not make changes outside the requested scope just because they seem like improvements. Suggest follow-up work separately.
