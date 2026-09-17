# OITUI — Project History & Context

*Compiled September 2026. This document exists for two reasons: to live in the OITUI GitHub repo as a project history, and to give any AI assistant (or human contributor) picking up this project full context without having to reconstruct it from scratch.*

**If you are an AI assistant reading this to get up to speed:** the most load-bearing sections for you are *Hard-Won Technical Lessons* and *The Debugging Journey* below — they capture failure modes that are easy to reintroduce if you reason from the source code alone without knowing the history. Read those before proposing changes to OITI or OITS.

---

## Quick Facts

| | |
|---|---|
| Maintainer | Wilburt (GitHub: `realtweety`), sole developer |
| Target | iPhone 8 Plus (notchless), jailbroken iOS 16.7.x |
| Jailbreak | Dopamine (rootless, semi-untethered) |
| Min iOS | 16.0 (`TARGET := iphone:clang:16.5:16.0`) |
| Build system | Theos, `THEOS_PACKAGE_SCHEME=rootless` |
| Build machine | Mac, macOS 27 beta / Xcode 27 beta (migrated off Windows/WSL) |
| Deploy | `make package install`, over SSH to `root@192.168.4.89` |
| Repo license | MIT (root `LICENSE`) — see *Licensing* section for a caveat |
| Status | Early development, actively iterating |

---

## What OITUI Is

OITUI (**Order In The User Interface**) is an attempt to bring the look and feel of modern iOS — Dynamic Island, Liquid Glass materials, a modern status bar layout — to older jailbroken iPhones that will never officially get it. The guiding line from the README: *"If Apple never ships it to older devices, we'll build it ourselves."* It's explicitly not a theme or a skin; it's meant to be a real, modular software effort, developed and tested primarily on an iPhone 8 Plus with performance treated as a first-class constraint from day one, not an afterthought.

OITUI is a family of separate tweaks/packages, each with its own `control` file and dependency on the shared `OITCore` library, rather than one monolithic tweak.

---

## The Modules

### OITCore
The shared foundation every other module links against (`OITCore.dylib`, MIT-licensed). It's small but genuinely load-bearing:
- **`OITLog`** — a toggleable structured logger.
- **`OITPreferences`** — a wrapper around `CFPreferences` (bool/float/int/string/object accessors). Notably patched so `floatForKey:` also accepts values stored as `NSString`, because `PSEditTextCell` specifiers with `isNumeric=false` store their value as a plain string rather than a number — this was silently breaking OITI's custom X/Y/scale fields before the fix.
- **`OITDeviceInfo`** — machine identifier via `sysctlbyname`, plus `isFullScreenDevice`/`hasDynamicIsland` heuristics based on safe-area insets.
- **`OITNotifications`** — Darwin notification observe/post helpers, plus `OITRequestRespring()`, a shared respring mechanism every module's Prefs "Respring" button calls into.
- **`OITViewUtilities`** — recursive view-tree traversal, first-descendant-of-class lookup, and `OITViewHasAncestorOfClass`. This last one turned out to be the single most reused piece of code in the whole project — it's what fixed both OITI's `SBFTouchPassThroughView` collateral-matching bug and OITS's App Switcher/Control Center mirrored-view bug (see *The Debugging Journey*).

An early retain-cycle bug in `OITObserveDarwinNotification` has been resolved, and the respring listener is now centralized in OITCore's constructor rather than duplicated per-module.

### OITI (Order In The Island)
A Dynamic Island simulation for devices that don't have one, forked from **VisibleIsland by ethxnn88**, used with written permission. Despite sometimes being described casually as "just the island," it already has real functionality:
- Per-device Y-offset table with hand-confirmed values for ~13 models (X through 14/13 Pro Max), plus a custom X/Y/scale fallback path for anything unsupported.
- Custom color and opacity for the Island's aperture.
- Notification banner repositioning, with three modes (device-fix, custom position, off).
- "Hide when not in use," and an outline-disable toggle.
- A MobileGestalt hardware-identity spoof (writes `ArtworkDeviceSubType`) to help pass certain system compatibility checks — this is the feature behind the MobileGestalt incident described below, and it's now backup/restore-safe.

OITIPrefs (its preferences bundle) has four controllers: Root, Color, Scale, Notifications.

### OITS (Order In The Status)
Originally built to do one thing — recenter the clock, since the 8 Plus is notchless and its stock clock is centered instead of left-aligned like a Dynamic Island device's. It grew into full status bar customization. All six elements are now implemented: **clock, battery, WiFi signal, cellular signal, carrier text, and network type**, each independently toggleable for reposition and hide, with a live-apply (no respring needed) preference-change path.

The architecture is: a recursive discovery pass finds and tags relevant views, a `CADisplayLink`-driven enforcer re-applies a transform to tracked views every tick, and dead (deallocated-window) views are pruned and rediscovered automatically. Carrier text and network type are special-cased: unlike the others, they have no dedicated class, so they're identified by sibling classification (leftover untracked `_UIStatusBarStringView` children of the foreground view, sorted left-to-right).

### OITInspector
A read-only diagnostic tool, not user-facing. It dumps the full live window/view hierarchy (`Latest-Windows.txt`) and a filtered scan of loaded classes matching status-bar/Island/connectivity-related name patterns (`Latest-Classes.txt`) to `/var/mobile/Documents/OITInspector/`. It's triggered either automatically a few seconds after SpringBoard launch, or on demand via a companion CLI tool, `OITDumpTrigger`, which just posts a Darwin notification. It touches nothing but its own log directory. This tool has been the single most important piece of infrastructure for every non-trivial OITS bug described below — nearly every real finding in this document came from reading one of its dumps rather than guessing from source.

### OITG (Order In The Graphics) — planned, not yet scaffolded
The intended Liquid Glass rendering engine. The plan (per `IDEAS.md`) is a single contained experiment once OITS is stable: wire `LGSharedGlassView` (already generic and reused elsewhere in liquidass, for its back button/sliders/switches) into just the *expanded* Island state — not the always-visible idle pill — and measure real cost on the 8 Plus (A11) before deciding how far to take it. No OITG code exists yet.

---

## Development Environment

Development moved from Windows/WSL Ubuntu to a Mac (macOS 27 beta, Xcode 27 beta) after WSL's `/mnt/c/` turned out to be the wrong home base for Theos projects — permission and performance problems. All Theos project work now lives in a native Linux-style home directory (`~/theos-projects`) on the Mac.

`TARGET` is deliberately pinned to `iphone:clang:16.5:16.0` because Xcode 27 defaults to the iOS 27 SDK, which is wrong for a project targeting iOS 16. A `Preferences.tbd → Preferences` symlink was added to the SDK to make the Preferences framework linkable for the prefs bundles.

Build and deploy is `make package install` from the Mac, over SSH to `root@192.168.4.89` (the iPhone 8 Plus). There's an ongoing, still-unresolved effort to get real on-device lldb debugging working via **XcodeRootDebug** (a jailbreak tweak that runs a root-privileged `debugserver` so Xcode can attach to arbitrary processes, including SpringBoard, not just apps it built). The device has been stuck showing as "Unknown/Offline" in Xcode's device list; cable, USB pairing, Developer Mode, and trust records have all been ruled out. This remains parked, not abandoned — see *Open Items*.

For local-LLM-assisted development (brainstorming, pair-programming on Logos/Objective-C), **Qwen2.5-Coder-14B at Q4_K_M** was identified as the best fit for a 16GB-VRAM card (4070 Ti Super), with **Devstral Small 2 24B** as an alternative for harder agentic tasks at the cost of usable context window.

---

## Hard-Won Technical Lessons

These are constraints discovered through real incidents, not assumptions — treat them as load-bearing when working on this codebase:

- **MobileGestalt writes are dangerous.** Writing `ArtworkDeviceSubType` without backing up the original value first caused a total homescreen/touch lockup that persisted even through removing the tweak. Always back up before writing a MobileGestalt value, and restore via a compiled helper invoked from `prerm` — not via `CFPreferences`, whose user-domain resolution is ambiguous in a root context.
- **Never write `.frame.origin` directly on pooled system status bar views.** Direct frame writes cause permanent view teardown (confirmed via debug logging showing `view.window == nil` afterward, i.e. the view got torn down and never came back). Transform-only repositioning (`CGAffineTransformMakeTranslation`) is the safe pattern.
- **Logos' `%hook` is class-wide, not context-aware.** Any hook on a status bar view class fires on *every* instance of that class anywhere in SpringBoard — including mirrored copies SpringBoard builds elsewhere for its own purposes. Confirmed so far: the **App Switcher** (a full second status bar tree per app card, for the preview) and **Control Center** (a full second status bar tree in its status "peek" area) both do this. **Lock Screen** does *not* do this — it renders its status content through an entirely different, non-UIKit path (see the Lock Screen finding below), so it's architecturally unreachable via hooking at all, not just a scoping problem. Scoping guards via ancestor-class inspection (`OITViewHasAncestorOfClass`) are necessary for the mirrored-window cases; there is no equivalent fix for Lock Screen with this approach.
- **`CADisplayLink` is the only safe enforcement point.** Reposition logic must run from the display link tick, not from system-invoked callbacks like `setFrame:` or `layoutSubviews` directly (those can still be used to *discover* and *tag* views, just not to apply the actual persistent correction).
- **`CFPreferences`'s user-domain is unreliable in a root context.** For anything an uninstall script (`prerm`, running as root) needs to read, use a flat plist file at an explicit fixed path instead.

---

## The Debugging Journey

This is the chronological story of how the above lessons were actually learned, and the current unresolved threads.

### The MobileGestalt incident (OITI)
Early in OITI's hardware-identity-spoof feature, writing the MobileGestalt cache value directly (with no backup) caused a total touch/homescreen lockup that survived tweak removal — the corrupted value was already committed to disk. The fix that shipped: a breadcrumb file (`/var/mobile/Library/Preferences/OITIGestaltBackup.plist`) records whether a backup was ever captured and what the original value was, written both from the live tweak (`OITIRootListController`) and mirrored into the breadcrumb on every toggle. A separate root-run helper tool, `OITIRestoreGestalt`, reads that breadcrumb and restores the original value; it's invoked automatically from `prerm` on genuine removal (not on the reinstall-in-place that happens constantly during development — the script explicitly checks `$1 == "remove"` to avoid restoring on every dev iteration).

### The permanent view-teardown bug (OITS)
Early status-bar repositioning wrote directly to `view.frame.origin`. This caused affected views to be permanently torn down by iOS — confirmed via debug logging showing `view.window` had gone `nil` and never recovered. The fix was architectural: never write frame directly; instead reset any incoming transform to identity in `setFrame:` (to neutralize whatever the system was about to do), let `%orig` proceed, and apply the actual desired offset purely as a transform, exclusively from the `CADisplayLink` tick loop, never from the callback itself.

### The OITS status bar saga
1. **Clock only, then six elements.** OITS started as a single-purpose clock recenterer. The same discovery→track→tick architecture was generalized to battery, WiFi, cellular, carrier text, and network type. Carrier text and network type needed a different classification approach (sibling sort by leftover, untracked, identity-transform string views) since neither has its own dedicated class.
2. **Validation.** Carrier text repositioning worked cleanly using the proven pattern, confirming it generalizes beyond the original two targets. A rare 1–3 frame "blink" (a missed correction cycle before the next tick catches it) was assessed and accepted as below the threshold of a real problem.
3. **The Xcode/lldb detour.** In parallel, an attempt was made to get real on-device debugging working via XcodeRootDebug, specifically to get better visibility into the WiFi instability described next. This hit a wall (device stuck "Unknown/Offline" in Xcode despite ruling out cable/USB/Developer-Mode/trust-record causes) and was consciously deprioritized in favor of continuing black-box OITS testing, on the reasoning that it's high-value but not blocking. It remains open.
4. **Instability surfaces.** Testing cellular and WiFi reposition in isolation showed both held position perfectly in a plain foregrounded app, but broke down around transitions: returning from the App Switcher, and — worse for WiFi — the Lock Screen, where nearly everything except battery disappeared.
5. **A useful mistake.** The first several OITInspector dumps meant to catch the "broken" state accidentally captured the Lock Screen instead (twice — and two pastes turned out to be byte-for-byte identical, revealing `OITDumpTrigger` hadn't actually been re-run between them). But this accident produced a real finding: on the Lock Screen, **none** of the six tracked status-bar view classes exist anywhere in the entire window hierarchy. This matched an earlier, independent finding (logged via an OITInspector class scan) that `SBMainDisplaySceneLayoutStatusBarView` is a full-screen container with **zero UIView children** — meaning Lock Screen status content is rendered through a private, non-UIKit-addressable mechanism. This class of "disappears on Lock Screen" bug was written off as out of reach for the current hooking approach entirely, not something to keep chasing.
6. **The real App Switcher root cause.** Once `OITDumpTrigger` was actually re-run correctly, a dump captured mid-transition revealed that `SBMainSwitcherWindow` contains a second, fully real copy of the entire status bar hierarchy (`UIStatusBar_Modern → _UIStatusBar → _UIStatusBarForegroundView`, with genuine `_UIStatusBarStringView` / `_UIStaticBatteryView` / `_UIStatusBarWifiSignalView` instances) — built to render each app's card preview. Because Logos hooks are class-wide, every OITS hook was also firing on this mirrored copy, applying offsets calibrated only for the primary status bar's coordinate space.
7. **The fix, and confirmation.** An ancestor-class scoping guard, `OITSViewIsInsideAppSwitcher` (built on OITCore's `OITViewHasAncestorOfClass` — the same utility that had already fixed an analogous OITI bug on `SBFTouchPassThroughView`), was added to all six discovery functions and all four `setFrame:` hooks. On-device testing confirmed cellular stability genuinely improved.
8. **A second mirror, in Control Center.** A later dump — this time deliberately capturing Control Center, which happened to be frontmost — showed the identical problem exists a second time: `SBControlCenterWindow` contains its own separate, real copy of the same status bar view classes in its status "peek" area.
9. **The crash-loop.** The same guard was widened to also exclude `SBControlCenterWindow`. After rebuild and install, **none** of the six repositioning features worked at all. Diagnosis: `/tmp/OITSDebug.log` showed the tweak's constructor firing three times within under three minutes — the signature of SpringBoard crash-looping — corroborated by a crash report timestamp landing right on one of the relaunches.
10. **The revert, and the discipline.** Rather than reason further from source code (which read as correct on paper), the Control Center exclusion was reverted back to the last confirmed-stable, App-Switcher-only version. The Control Center mirrored-view bug is real and still open, but is explicitly parked until the actual crash log content (grepped for "oits") is examined — evidence before another attempt, not another theory.

---

## Current State Snapshot

**OITCore** — all five source files built and confirmed working. The `OITObserveDarwinNotification` retain-cycle bug is resolved; respring handling is centralized; `floatForKey:` correctly handles string-backed numeric preference values.

**OITI** — OITIPrefs complete with four controllers. MobileGestalt corruption incident resolved via the breadcrumb backup/restore system. `OITISafeScaleValue()` clamping prevents degenerate transform lockups from bad scale input; the curtain-hide logic correctly accounts for `scaleEnabled` now too.

**OITS** — all six elements implemented. Transform-only repositioning applied exclusively from the `CADisplayLink` tick resolved the permanent-teardown bug. The App Switcher scoping guard is implemented and confirmed improving cellular stability. **WiFi repositioning remains unstable and is currently accepted as best-effort** (self-heals via periodic rediscovery, but genuinely fragile around certain transitions).

**OITInspector** — stable, in active use as the primary diagnostic tool for both OITS and OITI work.

**OITG** — not yet scaffolded; still at the planning stage described in `IDEAS.md`.

---

## Diagnostic Workflow

The established, working way to investigate a live view-hierarchy problem:

```bash
ssh root@192.168.4.89
/var/jb/usr/libexec/OITDumpTrigger      # triggers a fresh dump — do this every time, it does not auto-refresh
cat /var/mobile/Documents/OITInspector/Latest-Windows.txt
```

Always check the timestamp at the top of the dump before trusting its contents — a stale dump (trigger not re-run) looks identical to a fresh one otherwise, and this has caused real wasted cycles before. Capture the dump *in* the exact state you're trying to diagnose (e.g., immediately after a transition, or with only one reposition toggle active at a time) rather than a generic "afterward" snapshot.

For runtime debugging without lldb, flat-file logging to `/tmp/OITSDebug.log` (via `OITSDebugLog`) is the fallback, and has been sufficient to diagnose everything so far, including the crash-loop signature (repeated `=== ctor ===` lines within a short window).

**Working style established over this project:** reason carefully about consequences before editing rather than iterating speculatively; prefer full-file rewrites over patch-style diffs when sharing code; and — critically — when a change produces a crash-loop, revert to the last known-good state immediately and gather evidence (crash logs, debug logs) before attempting a fix a second time, rather than re-reasoning from source code alone.

---

## Open Items / Roadmap

The full feature brainstorm/backlog lives in `IDEAS.md` at the project root — it's a menu, not a committed roadmap, and includes things like Island-native notifications (next up once OITS is functional), a modular `Modules/` split for `Tweak.xm`, an Apple-Mode-vs-Enhanced-Mode toggle, a developer/debug overlay, and a longer list of "interesting but needs its own design pass" and "explicitly deferred" ideas (a plugin SDK, anything needing live third-party network calls, a separate "Island Studio" companion app, merging OITS and OITI into one engine — all deferred as a different risk/complexity class, not just lower priority).

Near-term, concrete open items:
- **Control Center mirrored-view bug** — real, confirmed, parked pending actual crash log evidence (grep the newest `SpringBoard-*.ips` in `/var/mobile/Library/Logs/CrashReporter/` for "oits") before re-attempting the exclusion.
- **Cellular-to-WiFi network-switch disappearing symptom** — reported but not yet captured in an OITInspector dump at the exact transition moment; needs that dump before a fix is proposed.
- **A small default-value mismatch**: `sNetworkTypeLeadingOffset`'s code fallback is `100.0` but `Root.plist`'s slider default is `80.0`. Cosmetic unless the preference key was never set, but worth aligning.
- **OITG needs to be scaffolded** as an actual module — currently plan-only.
- **lldb via XcodeRootDebug** remains an open goal, parked after the device got stuck "Unknown/Offline" in Xcode.
- A Dynamic Island reference device is planned for future OITI testing on actual DI hardware, rather than only simulated behavior on the 8 Plus.
- An `arm64e` new-ABI limitation on Linux has been flagged as a future concern for OITI Dynamic-Island builds; GitHub Actions macOS runners have been identified as a workaround if it becomes necessary.

Two confirmed Apple-internal leads worth investigating if the "status bar flows into the Island" idea is ever pursued for real: `SBSystemApertureStatusBarPillElementProvider` / `SBSystemApertureStatusBarPillElementProvider`-adjacent classes exist on-device and appear to be Apple's own connective tissue between the status bar layout system and the Dynamic Island; and `SBMainDisplaySceneLayoutStatusBarView` (mentioned above) is confirmed to render its content via a private/cross-process mechanism rather than addressable UIKit subviews, which is the actual reason Lock Screen status content can't be reached by hooking.
