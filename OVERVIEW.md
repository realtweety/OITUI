# OITUI Overview

OITUI is a multi-module iOS jailbreak tweak suite targeting rootless iOS 16 (Dopamine/palera1n-style packaging), built and maintained solo.

## Modules

- **OITCore**: Shared MIT-licensed foundation framework: logging (`OITLog` and the `OITLogger` file logger), preferences, device info, notifications, view utilities.
- **OITI**: Dynamic Island module, forked from [VisibleIsland](https://github.com/ethxnn88) by ethxnn88 (written permission obtained). Includes a standalone prefs bundle, OITIPrefs, and the `OITIRestoreGestalt` helper.
- **OITS**: Status bar element repositioning tweak (clock, battery, WiFi, cellular signal, carrier text, network type) plus per-element hide.
- **OITInspector**: Read-only diagnostic tool for live window hierarchy dumps. It cannot see the status bar content root (`_UIStatusBar`).
- **OITG**: Liquid Glass rendering, a GPL-3.0 fork of liquidass. Not scaffolded; intentionally deferred.

Related docs: `LEARNINGS.md` (constraints, safe patterns, lessons), `DIAGNOSTICS.md` (logging, dumps, how to read them), `COMMANDS.md` (every command, copy-paste exact), `WORKFLOW.md` (git, PRs, releases), `IDEAS.md` (backlog and research notes), `OITUI_HISTORY.md`, `CREDITS.md` and `LICENSES.md`.

## Where we left off (read first)

*Mid-October 2026 (14 Oct). This section is the hand-over for a new chat in the same project.*

### State of the repo
- **Released v0.1.0** (tag on `main` at `46cf122`, OITCore + OITI `.deb` files built on the Mac with `FINALPACKAGE=1`). Claude downloaded the `v0.1.0-1` and `v0.1.0-2` packages later and confirmed each binary has arm64 and arm64e slices; the `iphoneos-arm64` in the file name is only the rootless package label.
- **`main` holds tested code.** Work happens on one branch, `experiments`, and lands by pull request with a squash merge (`WORKFLOW.md`). After PR #4 GitHub auto-deleted `experiments`, so **recreate it from `main` before starting new work** (`COMMANDS.md`, section 10).
- Primary development machine is now the **Arch PC** (`~/OITUI`, fish shell). The Mac (`~/theos-projects/OITUI`) is used at school and for **release builds**.

### What exists and was tested on the iPhone 8 Plus (iOS 16.7.16)
- Step 1 cleanup (device table, single `%orig`, matching defaults, clamped scale).
- Step 2 safety: `OITLogger`, respring-loop guard and safe mode, MobileGestalt self-check, backup repair (a poisoned "original = 2556" backup is now recorded as absent), quiet-by-default diagnostics (level 0).
- **Island Size sliders** (OITI > Scale): width and height multipliers on Apple's `sensorRegionSize`. The Island itself shrinks while its content keeps normal size. Applies **live**. Owner's chosen minimal look: width 0.65, height 0.70.
- **X/Y scale sliders** (same page): separate width and height window transform that scales Island and content together. Applies live. The old single `scale` value migrated correctly.
- Island on/off through the settings switch (key removed and restored correctly).
- Status Bar Layout: no-op on the 8 Plus (not in the table, owner's manual provider override unaffected). Tested on a tester's iPhone 13 mini only.
- Diagnostic dumps with a METRICS section and class queries.

### Not verified, or known issues (owner chose to leave these)
- **Not run:** the uninstall `prerm` path (`OITIRestoreGestalt`), hide curtain / hide gain map toggles, and the release `.deb` files on a clean install.
- **Polish list:** banner position is slightly off at extreme Island sizes; custom color, opacity and banner offset do not apply live (they need a relayout request like the size sliders); the Scale page's X/Y sliders are absolute (their 1.0 is not Apple's size on this phone, see "Island research findings"); the "No built-in offsets" notice works.
- **OITS is broken on the owner's phone.** The owner manually set `UIStatusBarVisualProviderClassName` to `_UIStatusBarProvider_DynamicSplit` in `com.apple.UIKit.plist`. It looks good except the top half of the status bar clips into the top of the screen, and OITS positioning does not work with that layout class. Parked. `main` still has the OITS diagnostic build (`OITS-diag-2026-09-29-a`), which has never run in a clean state; do not ship OITS yet.

### Current focus: Island content
Own content in the Island (notifications, queue, progress bars, volume slider). The class dumps show Apple already has an element model that we may be able to use directly instead of an overlay window. See the plan below.
- **Status bar fix (14 Oct).** A Reddit user (iPhone 13 mini, iOS 16.5.1, NathanLR) reported a red status bar titled `rdar:45025538` with the Island on. Cause: with the 2556 spoof, UIKit's `+[_UIStatusBarVisualProvider_iOS visualProviderSubclassForScreen:visualProviderInfo:]` returns `nil` for his screen and iOS falls back to a placeholder. OITI now hooks that method (always `%orig`) and, under **Status Bar Layout = Automatic** (new picker at the bottom of the OITI settings page), returns the device's native provider while the Island is on. Interim GitHub releases `v0.1.0-1` (diagnostic) and `v0.1.0-2` (fix, a non-final `0.1.0-8+debug` build) were sent to the tester, who confirmed the bar is gone. `0.1.1` is the cleaned-up release that replaces them (`FINALPACKAGE=1`, `control` version 0.1.1).
- His native provider, read from his log with the Island off: `_UIStatusBarVisualProvider_Split1080_Wide`. The first fix used `Split1080` and also worked. His screen bounds are 375 x 812 points.
- **Status bar fix:** only the iPhone 13 mini has a native provider read from a real log. Every other device uses a guess by native pixel width (828 for XR and 11, 1125, 1170, 1242, 1284), and the 828-pixel rule is untested. The `_Wide` variants probably belong to the iPhone 13 generation (smaller notch); not confirmed. The mini rows in `OITIDeviceProfiles.h` (`iPhone13,1`, `iPhone14,4`) now say 375 x 812 (the old 360 x 780 was wrong), which only matters for the banner fix and is untested on-device.
- The 0.1.1 refinements after the tester's log (native table, `nil` handling, level gating) were not re-run on the mini.

## Island research findings (iPhone 8 Plus, spoofed `ArtworkDeviceSubType` 2556)

**Window and layout**
- Apple's Island window (`SBSystemApertureWindow`) is a **360 x 640 canvas with a 1.15 transform** (frame 414 x 736), even with OITI scaling off. 1.15 = screen width / canvas width. There are two windows: one for `SBSystemApertureWindowScene` (content) and one for `SBSystemApertureCurtainWindowScene` (curtain).
- View chain: window > `SBSystemApertureCaptureVisibilityShimViewController` > `SBSystemApertureViewController` > `SAUIElementViewController` > `SAUIElementView` > `_SAUIProvidedViewContainerView` > `_SAUIPortalView` (CAPortal-hosted content). When idle there is no element view controller, only the bare container.
- Stock pill sizes in window units (multiply by 1.15 for screen points): idle 125.0 x 36.7, lock screen 165.7 x 36.7, Spotify compact 189.0 x 36.7, timer 201.0 x 36.7, Spotify expanded 337.3 x about 325. Compact height is always 36.7. Width = sensor region (125) + the content's outsets.

**`SBUISystemApertureLayoutMetrics` (SpringBoardUIServices)**
- A shared object (`+sharedInstanceForEmbeddedDisplay`) with about 24 computed getters and no stored state. Values here: `sensorRegionSize` 125 x 36.667, `_inertSize` the same, `minimumCompactSize` 125 x 36.667, `maximumCompactSize` 286.667 x 36.667, `maximumExpandedSize` 337.333 x 337.333, `minimumExpandedSize` 337.333 x 84, `compactConcentricAreaSize` 36.667 x 36.667, `compactLegibleAreaInsets` leading/trailing 10, `maximumLeadingTrailingViewSize` 80.667 x 36.667, `minimumMinimalSize` 36.667, `maximumMicroNoticeSize` 293.333 x 66.667, `minimumContinuousCornerRadius` 18.333, `interSensorRegionInWindowSpace` (213.333, 11.333) 9 x 36.667. Class methods: `_nativeScreenWidth` 360, `_deviceNativeScreenSizeIsLargePhone` NO.
- **`sensorRegionSize` is the root input.** Everything else derives from it. Hooking `_inertSize` alone changed derived numbers but no pill sizes. OITI hooks only `sensorRegionSize` and multiplies it (live, via a relayout request). Icons, artwork and text stay stock size.

**Apple's content model (candidates for our own content)**
- `SBSystemApertureProvidedContentElement` (`initWithIdentifier:contentProvider:`) has `leadingView`, `trailingView`, `minimalView`, preferred and supported layout modes, and edge outsets.
- `SBUISystemApertureCustomContentProvider` (`initWithView:`, `providedView`, `contentColor`) wraps any view as content.
- `SBUISystemApertureElementConfiguration` (leading/trailing/minimal views, `keyColor`, `launchURL`, layout modes, `preferredCustomLayout`) and `SBUISystemApertureElementSource` are the client-facing pieces.
- `SAUISystemApertureManager` has `registerElement:`, `registeredElements`, `orderedElementViewControllers` and `_maximumNumberOfSimultaneouslyVisibleElements`. `SBSystemApertureElementAuthority` has `elementsOrderedByPromotionFromTemporallyOrderedElements:withPreviousOrdering:` (the priority and queue logic). `SBSystemAperturePresentableManager` registers and invalidates elements.
- `SBChargingSystemApertureElementProvider` (`powerElementWithBatteryCapacity:`) is a SpringBoard-side example of creating an element.
- Open questions: how to obtain the live `SAUISystemApertureManager`, and what protocol an element must satisfy.

### Plan (Island content)
1. **Research hooks (log-only, level 1).** First dump the device's method encodings and loaded aperture protocols; only then install log-only hooks for `-[SBSystemApertureProvidedContentElement initWithIdentifier:contentProvider:]` and `-[SAUISystemApertureManager registerElement:]` while charging, Spotify and a timer are active (identifiers, content provider classes, layout modes). Capture the manager instance. This order avoids guessing private method ABIs. The dump reports matching protocol names and the relevant registration/provider signatures.
2. **Proof of concept:** create one custom element (a "hello" leading label) on demand, using the charging provider as the template.
3. **Then:** Island-native notifications, the queue and stacking logic, progress bars. The volume slider is separate (it needs OITI to load into MediaRemoteUI; see Licensing).

**Notification requirement:** a user-facing notification element must have its own Settings toggle, `islandNotificationsEnabled`, defaulting to `NO`. When off, OITI must not create or present its custom notification element; the existing iOS notification path and OITI's separate banner-position settings remain available.

## Module state

### OITCore
- Sources: `OITLog` (legacy `OITLog()` plus `OITLogger`: async file logger, rate limiting, stack budgets, state-change helper, default level 0), `OITPreferences`, `OITDeviceInfo`, `OITNotifications` (Darwin notifications, `OITRequestRespring`), `OITViewUtilities`.
- Headers are installed into `$THEOS/include/OITCore` by the OITCore build. OITI and OITS compile against that copy, so rebuild OITCore first when it changes.
- Macro parameters in `OITLog.h` end in `_` so they cannot collide with selector keywords.

### OITI
- **Architecture:** OITI is not an Island renderer. `islandEnabled` writes `ArtworkDeviceSubType = 2556` into the MobileGestalt cache (backed up first, breadcrumb at `/var/mobile/Library/Preferences/OITIGestaltBackup.plist`, restored by `OITIRestoreGestalt` from `prerm`) so iOS 16 builds its real SystemAperture. `Tweak.xm` then hooks `SBSystemApertureWindow` (position and scale transform), `SBBannerWindow` (banner position), `_SBSystemApertureMagiciansCurtainView` and `_SBGainMapView` (hide), `_SBSystemApertureContainerViewContentView` (background color), `SBFTouchPassThroughView` (transparency, line hiding) and `SBUISystemApertureLayoutMetrics` (`sensorRegionSize`, the Island Size). Island content (music, timers) comes from Apple.
- **Process scope:** OITI's constructor returns immediately outside SpringBoard.
- **Safety:** respring-loop guard (5 launches in 120 s trips safe mode, hooks not installed; cleared by removing `OITISafeMode.plist` or reinstalling), startup self-check (`CHECK` lines), backup repair in the prefs bundle (opening settings or toggling the switch).
- **Settings pages:** Root, Color, Scale (Island Size sliders, X/Y scale sliders, resets), Notifications. Settings write the domain `com.wilburt.oiti.prefs` and post `com.wilburt.oiti/PrefsChanged`.
- **Diagnostics:** level 0 by default (only `SESSION`, `GUARD`, `SAFE`, `CHECK`). Level 1 enables events, the trigger-file poll and dumps. See `DIAGNOSTICS.md`.
- **Known fragile spots:** `frame.origin` is written on a transformed window in `layoutSubviews`; the `SBBannerWindow -frame` getter returns constants; the `subviews.count == 4` heuristic on `SBFTouchPassThroughView` may change between iOS versions.
- **Device table:** 17 models in `OITIDeviceProfiles.h`, seven marked verified. The 8 Plus has no entry and uses the custom path.
- **Status bar layout:** `StatusBarLayout` (auto, off, or a `_UIStatusBarVisualProvider_*` name). Hook group `OITIStatusBarHooks` (separate from `OITIHooks`, same safe-mode rule). `CHOICE` lines at level 0, boot report and `LIVE` lines at level 1 (`DIAGNOSTICS.md`, `COMMANDS.md` section 12).

### OITS
- Six elements implemented; repositioning was confirmed on-device on the stable build. It is transform-only and applied only from the `CADisplayLink` tick. Offsets are converted into the parent's pre-scale space.
- `main` contains the **diagnostic build** (`OITS-diag-2026-09-29-a`): same behavior plus extensive logging. Defaults are now quiet (`DiagnosticsLevel` 0). The newer fixes in the old plan (time-like clock detection, disable sweep, `PROVIDER` dump line) were never committed anywhere and would have to be rebuilt.
- Still missing: the App Switcher / Control Center mirrored-view scoping guard. OITS is broken on the owner's phone for the reason in "Not verified" above.

## Licensing

- MIT for OITCore. OITI / OITS licensing is still undecided. OITG is planned to use liquidass (GPL-3.0).
- **Crescendo** ([Yves000/Crescendo](https://github.com/Yves000/Crescendo), GPL-3.0) only served as a reference. No code was copied. If a volume slider is added, write it clean-room from Apple's own classes, with separate toggles for the lock screen player and the Island player. Useful patterns: one predicate for visibility, expiring cross-process state, weak-captured view controllers in delayed blocks.
- Attribution and licensing live in one project-wide `CREDITS.md` and one `LICENSES.md`.

## Toolchain

- **Machines:** Arch PC (primary, repo `~/OITUI`, Theos `~/theos` with `iPhoneOS16.5.sdk`, fish) and Mac (repo `~/theos-projects/OITUI`, `TARGET` pinned to `iphone:clang:16.5:16.0`). Arch builds print "incompatible arm64e ABI compiler" warnings: harmless on the arm64 iPhone 8 Plus, but **do not publish `.deb` files built on the Arch PC**.
- **Packaging:** Theos rootless (`THEOS_PACKAGE_SCHEME=rootless`). Release builds use `FINALPACKAGE=1` (no `+debug`). All `control` files say `Version: 0.1.0`; dpkg sorts `0.0.10` below `0.1.0`, so keep versions ascending. OITI depends on `com.wilburt.oitcore`, so a release needs both packages.
- **Deploy:** USB only. Run `iproxy 2222 22`, then `THEOS_DEVICE_IP=localhost THEOS_DEVICE_PORT=2222 make package install` (Mac: `127.0.0.1`). WiFi SSH stopped resolving in September 2026.
- **GitHub:** `gh auth login` and `gh auth setup-git` on each computer. The repo accepts squash merges only and deletes merged branches.
- **Test device:** iPhone 8 Plus, jailbroken iOS 16.7.16. No real Dynamic Island hardware is available.

## Status bar layout investigation (history)

- **Layout swap technique.** The third-party tweak [Little16](https://github.com/michaelmelita1/Little16) overrides `_UIStatusBarVisualProvider_iOS`'s `+class` to return a different Apple-native visual provider. Experiments: `_UIStatusBarVisualProvider_RoundedPad_ForcedCellular` works; `_UIStatusBarVisualProvider_Phone` caused an infinite SpringBoard crash loop; `_UIStatusBarVisualProvider_Split1080` did not crash but rendered scaled up and clipped.
- **Why Split1080 looked wrong.** `_UIStatusBarForegroundView` carried a uniform 1.104x transform (bounds 375 x 49.82, frame 414 x 55): the layout is built for a 375 pt canvas and stretched, so child frames live in pre-scale space. Any correction has to account for that scale. The Island window has the same kind of canvas scaling (1.15).
- **Outcome.** Changing GesturesXV's Status Bar Style to "Legacy" gave a modern, correct status bar; the exact mechanism was never root-caused. In October 2026 the owner instead set `UIStatusBarVisualProviderClassName` to `_UIStatusBarProvider_DynamicSplit` by hand (see above).
- BarOnLandScape (a separate tweak) was resetting the clock's transform every 150 ms in old logs. It is not part of OITUI.
- **Red `rdar:45025538` bar (Oct 2026).** Seen first on iPhone XR and 11 (VisibleIsland's README), then on an iPhone 13 mini. It appears with the spoof on even when none of OITI's hooks are installed, so it comes from the spoof. A class dump found the real selector: `+[_UIStatusBarVisualProvider_iOS visualProviderSubclassForScreen:visualProviderInfo:]` (returns a `Class`; the older `+class` and `_implementationClass` probes do not choose the provider on iOS 16.7). On the mini it returns `nil` with the Island on and `_UIStatusBarVisualProvider_Split1080_Wide` with it off. Fixed by returning the native provider in that case. `_UIStatusBarVisualProvider_Fallback` exists but was not what UIKit returned.

## Open items

- Island content research and proof of concept (above).
- Polish: live color, opacity and banner offset; banner position at extreme sizes; make the X/Y scale relative to Apple's own size (new keys, no migration); lower the Island Height slider minimum if wanted (about 0.6 is where 22 pt artwork stops fitting, untested).
- OITS: revert or adapt to the new layout class, rebuild the lost diagnostic fixes, restore the scoping guard.
- Test the uninstall path and the release packages on a clean install.
- Table entries for iPhone 8 / 8 Plus (`iPhone10,1/10,2/10,4/10,5`) once measured.
- lldb debugging via XcodeRootDebug/USB was attempted unsuccessfully and remains an open goal. OITG is deferred.
- Status bar fix: collect a native provider from other devices (Island off, `grep CHOICE`), especially iPhone XR and 11, 12 mini and the 12/13 families; add them to `OITINativeProviderNameForScreen`. Idea for later: record the native provider to a flat plist whenever `CHOICE` runs with the Island off (the default after install), and use that instead of a table.
- Make safe mode visible in the settings page and reconsider the 45 s stability window: a tester tripped it in 100 s by respringing while changing settings, and every later setting then silently did nothing.

## Starting a new chat

1. Upload `OVERVIEW.md`, `LEARNINGS.md`, `IDEAS.md`, `DIAGNOSTICS.md`, `COMMANDS.md` and `WORKFLOW.md`. Do not re-upload source; upload only the specific files a task needs.
2. Say which task to start from "Plan (Island content)" above.
3. Claude can clone the public repo in its sandbox to read code, but cannot run git on your machines, view GitHub web pages, or use the GitHub API reliably (rate-limited). Give it terminal output as pasted text and large logs as uploaded files.
4. Deliveries come as a `.tar.gz` of full files with repo-relative paths; extract it on `experiments` with `tar -xzf` (`COMMANDS.md`, section 10).
