# OITUI Development Notes

Hard-won technical constraints, safe patterns, and workflow lessons from OITUI development.

## Technical constraints

- **MobileGestalt writes are dangerous.** Writing `ArtworkDeviceSubType` without backing up the original caused a total homescreen/touch lockup that persisted through tweak removal. Always back up first, and restore via a compiled helper invoked from `prerm`. Do not use `CFPreferences` for this (its user-domain behavior is ambiguous in a root context).
- **Never write `.frame.origin` on pooled system views.** Direct frame-origin writes on system status bar views caused permanent teardown (`view.window == nil`). Transform-only repositioning is the safe pattern.
- **Apply corrections only from `CADisplayLink`.** Do not apply them from system-invoked callbacks such as `setFrame:` or `layoutSubviews`. Hooks may reset state and record natural positions; the tick reapplies.
- **Global Logos class hooks fire on every instance.** App Switcher, Control Center and the lock screen contain mirrored copies of hooked status bar views, so scoping guards are needed. The lock screen is architecturally unreachable by this approach.
- **Use flat plist files at explicit paths** for data that uninstall scripts must read. `CFPreferences` user-domain access is unreliable in a root context.
- **Keep Theos projects in the native Linux home directory** (for example `~/theos-projects`), not under WSL's `/mnt/c/`.

## Status bar internals (observed on iOS 16.7)

- **There are several `_UIStatusBar` instances at once.** The persistent one lives in `UIStatusBarWindow`; each app gets another inside an app-switcher page in `SBMainSwitcherWindow`; the cover sheet has its own. The inactive instance is hidden by fading its `UIStatusBar_Modern` ancestor to alpha 0, so "alpha 0 on an ancestor" is normal, not a bug.
- **Views are pooled and re-used.** The same view instance is detached and re-attached repeatedly, so transforms applied to a view persist across re-use. Anything that stops tracking a view must also reset it, and "forget on window loss" is not the same as "reset".
- **Slots can hold more than one view.** The time view and the carrier/network text view can share a slot and swap with a crossfade (alpha 0, scale 0.75), detaching the time view in between. Never identify the clock by "it's the only string view"; use its text (for example, a digit plus `:` or `.`).
- **Visual providers choose the layout.** A Split provider lays content out for a fixed reference width and stretches the foreground view with a uniform scale transform. Child frames are in pre-scale space, so convert desired on-screen offsets by dividing by the parent scale.
- **Third-party tweaks hook the same views.** Hook `setTransform:`, `setHidden:` and `setAlpha:`, flag your own writes, and log the call stack for everyone else's. The stack names the culprit dylib. This is how a separate landscape-status-bar tweak was found resetting the clock's transform every 150 ms.

## Debugging and logging practice

- **Log state changes, not every tick.** Compare a compact signature per view and log only when it changes.
- **Rate-limit every log line** by key, and count what was dropped. A 60 Hz path can otherwise flood the log and stall the main thread.
- **Write logs asynchronously** on a private serial queue. Open, append and close per line so deleting the file while running just starts a fresh one. Rotate by size.
- **Give stack traces a per-event-type budget.** A single global budget was used up by one repetitive event before the interesting ones occurred.
- **Log a session header** with a build tag and PID on every start. More than one session in a file means SpringBoard restarted.
- **Add a visibility watchdog** that reports why a view is invisible (hidden or alpha on an ancestor, off-screen, no window) and auto-dumps the hierarchy the first few times.
- **Review state flags for dead code.** The `sPrevious*Enabled` flags in OITS were declared and read but never assigned, so reset-on-disable could never fire.
- **Full-tree window walks are not free.** A discovery walk across all windows every 10 ticks measured 2–4 ms; prefer targeted discovery from the foreground view.

See `DIAGNOSTICS.md` for the OITS tags, trigger file and commands.

## Phone shell and rootless pitfalls

- zsh on the phone does not treat `#` as a comment in interactive mode, so inline comments become arguments. Do not paste commands with trailing comments.
- Shell functions such as a `mark` helper must be defined in the phone's shell, not the Mac's.
- `/tmp` is sticky: files created by root over SSH cannot be replaced or deleted by `mobile` (SpringBoard). Detect trigger files by modification time rather than by deleting them.
- `find` does not follow symlinks, so tweak directories behind symlinks (for example `/var/jb/Library/MobileSubstrate/DynamicLibraries`) can be missed. List them directly.

## OITI internals (observed in code review)

- OITI works by spoofing `ArtworkDeviceSubType` (2556) so iOS builds Apple's real Dynamic Island, then repositions and restyles it. Any feature that needs its own Island content needs a separate mechanism.
- The original code had six copies of one device if/else chain, so lists drifted apart (the prefs "supported devices" list omitted the iPhone 12 family that the tweak handled). Keep one table and have everything read it.
- Calling `%orig` unconditionally at the top and again inside branches runs layout twice. Call it once.
- A hook that replaces `didMoveToWindow` without calling `%orig` skips Apple's own work. Always call it.
- Don't force `hidden = NO` on a system view when your feature is off. Track that you hid it, and only undo that.
- Defaults in code must match the globals and the prefs UI. Mismatched defaults (`alpha` 0.0 against 1.0, `yPos` 0.0 against 20.5) made features look broken until a slider was touched.
- Check `|` against `||`: `a && !b | a && !c` parses very differently from what it looks like.
- Use the clamped value consistently. The Island's Y divisor used the raw scale while the transform used the clamped one.
- Overriding a getter or setter for unknown devices must fall through to the original, not swallow it. `-setFrame:` used to be swallowed entirely on devices with no table entry.

## Working with Claude across chats

- Large uploads and many tool calls use a lot of usage. Hand over the docs (`OVERVIEW.md`, `LEARNINGS.md`, `IDEAS.md`, `DIAGNOSTICS.md`) rather than re-uploading source, and upload only the specific files a task needs.
- GitHub folder (`/tree/`) pages cannot be read by Claude. Upload files or paste the individual file URLs.
- Prefer small, staged tasks with one complete deliverable each.

## Ways of working

- Reason about consequences before editing code; avoid speculative iteration.
- Prefer full-file rewrites over patch-style diffs.
- Split large changes into stages, each a complete, buildable file.
- Revert to the last known-good state when a change produces a crash loop, then investigate before re-attempting.
- Capture evidence before changing code: a log or dump from the exact moment of the symptom beats a plausible theory.
- Mark untested work clearly and keep it on a branch until it has run on-device.

## Tools and resources

- **Live hierarchy inspection:** FLEX (reaches `_UIStatusBar`, which OITInspector cannot) and the OITS diagnostic dump.
- **Runtime logs:** flat-file logs readable over SSH, plus SpringBoard crash logs in `/var/mobile/Library/Logs/CrashReporter/`.
- **Local LLMs for future small debugging** once everything is working: Qwen2.5-Coder-14B at Q4_K_M (best fit for a 16 GB GPU) and Devstral Small 2 24B for harder agentic tasks.
