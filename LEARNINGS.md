# OITUI Development Notes

Hard-won technical constraints, safe patterns, and workflow lessons from OITUI development.

## Technical constraints

- **MobileGestalt writes are dangerous.** Writing `ArtworkDeviceSubType` without backing up the original caused a total homescreen/touch lockup that persisted through tweak removal. Always back up first, and restore via a compiled helper invoked from `prerm`. Do not use `CFPreferences` for this (its user-domain behavior is ambiguous in a root context).
- **A backup is only as good as when it was taken.** OITI once captured "original = 2556" while the spoof was already in the cache, so turning the Island off wrote the spoof back (a silent no-op) and uninstalling would have left it in place. Never record the spoof value as the original on hardware that does not natively report it (only the iPhone 14 Pro, `iPhone15,2`, does on iOS 16); record the original as absent so a restore removes the key and iOS recomputes it. Never capture a backup when the cache could not be read. Take a snapshot copy of the cache before any risky test.
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
- **The visual provider is chosen in `+[_UIStatusBarVisualProvider_iOS visualProviderSubclassForScreen:visualProviderInfo:]`** (returns a `Class`, takes the screen and an info dictionary, which was `nil` in every observed call). `_UIStatusBar` keeps `_visualProviderClass` and `_visualProviderInfo` and builds the provider in `-_prepareVisualProviderIfNeeded`. `+class`, `+_implementationClass` and `+_statusBarImplementationClass` do not choose it on iOS 16.7.
- **The provider family is keyed by native pixel width:** `Split828`, `Split1080`, `Split1080_Wide`, `Split1125`, `Split1170`, `Split1170_Wide`, `Split1242`, `Split1284`, `Split1284_Wide`, plus `DynamicSplit` and `DynamicSplitMedium` for Island hardware. A 13 mini natively gets `Split1080_Wide`. `_UIStatusBarVisualProvider_Fallback` is a separate placeholder class.
- **The red `rdar:45025538` bar comes from the spoof alone.** With `ArtworkDeviceSubType` 2556 on a screen UIKit does not expect, the selector returned `nil` (an iPhone 13 mini). The fix is to return the native provider while the Island is on, and to log what UIKit chose with the Island off.
- **`UIScreen` scale lies on minis:** an iPhone 13 mini reports bounds 375 x 812 with scale 3.0, but its native bounds are 1080 x 2340 (native scale 2.88). The old 360 x 780 table entry was wrong.

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

## Island internals (iOS 16.7, spoofed 2556)

- **The Island window is a scaled canvas.** `SBSystemApertureWindow` is 360 x 640 with Apple's own 1.15 transform (screen width / canvas width), even with every OITI setting off. Setting your own transform replaces Apple's, so an absolute scale of 1.0 is not Apple's size (it is 15% smaller on the 8 Plus). Compute any "relative to stock" factor as screen width / window bounds width.
- **Size comes from `SBUISystemApertureLayoutMetrics`, and `sensorRegionSize` is the root.** `_inertSize`, `minimumCompactSize`, the compact padding areas and the corner radius all derive from it. Scaling only its return value shrinks the pill while icons, artwork and text keep stock size. Hooking `_inertSize` alone changes derived numbers but no pill size. Apple re-reads the getter on every layout, so a relayout request makes changes live.
- **A window transform scales content too**, so it cannot shrink only the pill. Compact pill width = sensor region + content outsets; compact height is constant.
- **Content is hosted, not drawn in place.** Element content sits in `_SAUIProvidedViewContainerView` > `_SAUIPortalView` (CAPortal). Idle has no element view controller at all.
- **Element model to build on:** `SBSystemApertureProvidedContentElement` + `SBUISystemApertureCustomContentProvider`, registered through `SAUISystemApertureManager`, ordered by `SBSystemApertureElementAuthority`. `SBChargingSystemApertureElementProvider` is a working SpringBoard-side example.
- **Dump workflow.** Put the phone in a state, run `dumpstate <label>`, upload the log. Dump class lists in small batches (5 classes) so the logger's backlog limit does not drop lines.

## Island elements (iOS 16.7, observed building Island Notifications)

- **Register through `SBSystemApertureController -registerElement:`.** It is the registrar SpringBoard's own providers use (it is also the element registrar of `SBSystemAperturePresentableManager`). The registration is a `SAUIElementAssertion`; `invalidateWithReason:layoutModeChangeReason:` removes the element. Capture the controller from its `-initWithWindowScene:` and its first `-registerElement:`. Calling `SAUISystemApertureManager registerElement:` directly appears to work but leaves the element without a host.
- **Apple classifies every element.** The manager asks `respondsToSelector:` for `hasIndicatorBehavior`, `hasAlertBehavior` and `hasActivityBehavior`. A bare `SBSystemApertureProvidedContentElement` answers none, so `-[SAUISystemApertureManager _elementViewControllerForElement:creatingIfNecessary:]` returns nil without ever calling `SAUIElementViewController initWithElementViewProvider:`, and `_reevaluatePromotedElements` then throws on `-[NSArray insertObject:atIndex:]` (object cannot be nil). **That uncaught exception aborts SpringBoard** and loops it. OITI's element is a runtime subclass (`objc_allocateClassPair`) that answers `hasAlertBehavior` YES, the other two NO, and `preferredAlertingDuration:` (like the charging alert).
- **The "identifier" of `initWithIdentifier:contentProvider:` is an object, not a string.** Real elements pass their own provider (`SBLockElementViewProvider`, `SBChargingSystemApertureElementProvider`). It must answer `elementIdentifier` and `clientIdentifier` (`com.apple.springboard` for SpringBoard-owned elements). An `NSString` throws `-[__NSCFString elementIdentifier]: unrecognized selector`; a small stub that answers those two (and logs anything else it is asked) works.
- **Content structure.** `SBUISystemApertureContentProvider` is the container (setters for leading, trailing, minimal, primary, secondary and action content view providers). Each holds a wrapper with `providedView`: `SBUISystemApertureCustomContentProvider initWithView:`. Using the wrapper as the element's whole content provider leaves every view nil.
- **Layout modes (min / max / preferred).** Observed: lock 1/1/1, status bar pill 1/2/2, in-call scene 1/3/2, charging -1/2/2. An element with 1/3/3 reports `layoutMode=3` and shows the expanded layout (icon, title, message, about 337 x 82 in window units, 98 high for a longer message). 1 is compact and 3 is expanded (both confirmed on screen); 2 is the wide pill (unverified). In compact the icon showed but the trailing text did not; not understood yet.
- **Where it lands.** After registration `elementHost` and `layoutHost` are `SAUIElementViewController`; views sit in `SAUIElementView` inside `_SBSystemApertureContainerViewContentView`. The rounded shape comes from three ancestors (`_SBSystemApertureContainerViewContentView`, a clip view with `masksToBounds`, `SBSystemApertureContainerView`), all with the same radius.
- **Banner pipeline.** On 16.7.16 each banner arrives at `-[SBNotificationBannerDestination postNotificationRequest:]` (`v24@0:8@16`; the 2023 trace that suggested `postNotificationRequest:forCoalescedNotification:` is not this version). The request is an `NCNotificationRequest` (`content.header`, `.title`, `.subtitle`, `.message`, `sectionIdentifier`). Hiding the stock banner by fading `SBBannerWindow` until the destination's `presentedBanner` is nil leaves Notification Center, the lock screen list and Focus filtering intact; swallowing the dispatcher call (as some tweaks do) breaks them.
- **A tap should run the stock banner's own action.** While OITI's element shows, the stock banner is only faded: `BNContentViewController > SBNotificationPresentableViewController > NCNotificationShortLookViewController` are still in `SBBannerWindow`. `NCNotificationViewController -_executeDefaultAction:` (`v20@0:8B16`) runs what a tap on it runs, so Apple's own code opens the right conversation and dismisses the banner. The `NCNotificationRequest`'s `defaultAction` is nil on 16.7.16, so a URL-based approach finds nothing. Match the banner to the element by the request (`notificationRequest`). Fall back to the app launch when the banner is gone.
- **Gestures on the Island window.** Recognizers on the element's `SAUIElementView` and on `SBSystemApertureWindow` both receive touches (`cancelsTouchesInView = NO`, permissive delegate); the window one is the one that fired in testing. Make the window ones accept only touches that start inside the element, and guard against handling a gesture twice.
- **Hook by name pattern with an encoding check.** Find the method with `class_copyMethodList`, require the exact type encoding, install with `class_replaceMethod` and `imp_implementationWithBlock`, always call the original first, and log candidates when nothing matches. A wrong guess about a private ABI then costs a log line instead of a crash.
- **Wrap the throwing method, not the whole system.** The promotion guard catches only while one of OITI's elements is live and rethrows otherwise; it turned a crash loop into a one-line log with a stack.
- **Find the missing requirement by tracing what Apple asks.** Hook `respondsToSelector:`, `conformsToProtocol:`, `isKindOfClass:` and the accessors on the element class, filter to your own element, log each distinct message once and read the last question before the failure. Add log-only hooks on the lookup functions (`VCFOR`, `VCINIT`, authority `AUTH`) to see which call returns nil.
- **Keep experiment keys out of shipped pickers.** A leftover `defaults write` value from testing (`IslandNotificationsPoCLayout`) would have silently overridden the new Style picker, so the developer override got a new key name.

## Build, packaging and tooling pitfalls

- **Theos picks up headers from `$THEOS/include` before your project's.** A stale installed copy shadows your edit. Import the module's own header with quotes (`#import "OITLog.h"`) inside that module, and rebuild OITCore first so the install step refreshes the copy.
- **Macro parameters must not match selector keywords.** A parameter named `tag` also replaced the `tag:` part of `-logLevel:tag:format:` and produced "expected ']'" errors. Name parameters `tag_`, `level_`, and so on.
- **`-Werror` makes warnings fatal.** A header with any nullability annotation needs `NS_ASSUME_NONNULL_BEGIN` before every pointer in it; mixed-type `?:` operands need an `(id)` cast.
- **Arch builds warn "incompatible arm64e ABI compiler".** Harmless for arm64 devices; do not publish packages built there.
- **Package versions:** dpkg sorts `0.0.10` below `0.1.0`. The `-N` build counter is per machine, so "downgrading" warnings between machines are harmless. Release builds use `FINALPACKAGE=1`; clear `packages/` first (it keeps every earlier build) and ship OITCore with OITI because OITI depends on it.
- **The phone's `defaults` has no `delete` mode.** Write an explicit value (`-int 0`) instead.
- **`sbreload` can drop the SSH session.** Log in again and re-define shell helpers such as `dumpstate`.
- **`iphoneos-arm64` is only the rootless package label.** The binaries inside are fat arm64 + arm64e. Check a release by downloading it, then `ar x`, extracting `data.tar.*` and reading the Mach-O header. A package without `FINALPACKAGE=1` is versioned `X.Y.Z-N+debug`; do not ship one as a release.

## Git and release lessons

- **GitHub rejects account passwords for git.** Use `gh auth login` and `gh auth setup-git`.
- **Squash merge means the old branch is not an ancestor of `main`.** Delete it with `git branch -D` only after the PR shows as merged. Repo settings now squash-only with auto-delete, so `experiments` disappears after each merge.
- **Merge only after on-device tests.** PR #3 was merged a minute after the push and put untested code on `main`. The checklist in `WORKFLOW.md` exists for this reason.
- **Do not paste commands with inline `#` comments** into the phone shell or the Mac's zsh.
- **Look-alike GitHub repos exist.** A repo that copies a real tweak's files but has a README advertising a Windows `.exe` or a `.zip` download, unrelated topics, one star and no contributors is a malware pattern. Check the author, stars, forks and contributors, do not open the download, and prefer reading source over installing packages from unfamiliar repos. OITI's own code is written from scratch; other tweaks were used only as references for what is possible.
- **Pre-releases use a tilde and a tag with a dash.** `OITI/control` says `0.2.0~beta.1` (sorts below `0.2.0`), the tag is `v0.2.0-beta.1`, and the GitHub Release is marked pre-release.

## Working with Claude across chats

- Hand over the docs (`OVERVIEW.md`, `LEARNINGS.md`, `IDEAS.md`, `DIAGNOSTICS.md`, `COMMANDS.md`, `WORKFLOW.md`) rather than re-uploading source, and upload only the specific files a task needs. Long chats use a lot of usage; start a new one when a chat gets bloated.
- Claude cannot run git on your machines. It can clone the public repo in its own sandbox to read code, but GitHub web pages, `/tree/` pages and the API are unreliable (rate limits). Paste terminal output as text and upload large logs as files.
- Prefer small, staged tasks with one complete deliverable each. Deliveries are full files in a `.tar.gz` with repo-relative paths (extract with `tar -xzf` on `experiments`).
- Ask for exact copy-paste commands; add new commands to `COMMANDS.md`.
- **Remote testers:** a log from their phone beats theory. Ship one build with a read-only log and an opt-in fix, and put the choice in a settings picker so the tester does not need a terminal. Ask for one command at the end. Tell them to wait 2 minutes between resprings (safe mode).
- **A tester's first symptom can be a safe-mode side effect.** Check `grep -e SESSION -e SAFE` first: safe mode silently disables every hook while the spoof stays on.

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
