# OITUI Overview

OITUI is a multi-module iOS jailbreak tweak suite targeting rootless iOS 16 (Dopamine/palera1n-style packaging), built and maintained solo.

## Modules

- **OITCore** — Shared MIT-licensed foundation framework: logging, preferences, device info, notifications, view utilities.
- **OITI** — Dynamic Island simulation, forked from [VisibleIsland](https://github.com/ethxnn88) by ethxnn88 (written permission obtained). Includes a standalone prefs bundle, OITIPrefs.
- **OITS** — Status bar element repositioning tweak (clock, battery, WiFi, cellular signal, carrier text, network type) plus per-element hide.
- **OITInspector** — Read-only diagnostic tool for live window hierarchy dumps. It cannot see the status bar content root (`_UIStatusBar`); use FLEX or the OITS diagnostic dump for that (see `DIAGNOSTICS.md`).
- **OITG** — Liquid Glass rendering, a GPL-3.0 fork of liquidass. Not yet scaffolded as a real module; intentionally deferred.

Related docs: `LEARNINGS.md` (constraints, safe patterns, workflow), `DIAGNOSTICS.md` (OITS diagnostic logging and how to read it), `IDEAS.md` (feature backlog), `CREDITS.md` and `LICENSES.md` (attribution and licensing, maintained separately).

## Where we left off (read first)

*Early October 2026. This section is the hand-over for a new chat in the same project.*

- **Status bar:** looks right after changing GesturesXV's Status Bar Style (now "Legacy"). OITS repositioning works. OITS work is **paused**. The OITS diagnostic build (`OITS/Tweak.xm`, build tag `OITS-diag-2026-10-02-c`) is written but **untested**; keep it on a branch such as `oits-diag`.
- **Current focus: OITI.** The plan is Steps 1–4 below. **Step 1 is written but untested.**
- **Step 1 files (in `OITI/`):** `Tweak.xm`, `OITIDeviceProfiles.h`, and in `OITIPrefs/`: `OITIBaseListController.h/.m`, `OITIRootListController.h/.m`, `OITIColorListController.h/.m`, `OITIScaleListController.h/.m`, `OITINotificationsListController.h/.m`, `Makefile`. Copy them over the repo versions. The prefs `Makefile` now also compiles `OITIBaseListController.m`.
- **What Step 1 changed:**
  - One device table replaces six copy-pasted if/else chains. A script verified the six chains agreed for all 17 models before they were removed. The table is shared with the prefs bundle.
  - `layoutSubviews` now runs `%orig` once instead of twice.
  - `didMoveToWindow` hooks on the curtain and gain-map views now call `%orig`, and the curtain only un-hides what OITI hid.
  - The divisor for the Island's Y position now uses the clamped scale. Before, it used the raw value.
  - Turning scale off now resets the window transform live.
  - The appearance color now updates live.
  - Prefs defaults now match the globals: `alpha` 1.0, `yPos` 20.5, `yNot` 40. Before, they were 0.0, which gave a transparent color or an Island at y = 0.
  - A device with no table entry no longer swallows `SBBannerWindow -setFrame:`, and custom banner offsets now work there. With `fixEnabled` on, an unknown device falls back to custom position.
  - The three prefs controllers share one base class, and the supported-device check uses the table.
- **Test checklist on the iPhone 8 Plus** (it has no table entry, so it uses the custom path):
  - Custom position (x/y) takes effect.
  - Scale on and off both apply live.
  - Hide curtain and gain map still work.
  - Color and transparency changes apply without a respring.
  - Custom banner offset works.
  - Turning on `fixEnabled` shows "No built-in offsets".
  - There is no logging in OITI yet, so judge visually.

### Plan (OITI)
1. **Cleanup (done, untested).**
2. **Safety.**
   - Respring-loop guard: a counter file, and auto-disable OITI features after N respring cycles within M minutes.
   - Startup self-check: log when `islandEnabled` is on but the MobileGestalt cache no longer holds 2556.
   - Test the `OITIRestoreGestalt` helper (the `prerm` path).
   - Move the OITS logging core (async queue, rate limiting, state-change logs) into OITCore as `OITLog`.
3. **Research (needs device dumps).**
   - With a stock element active (music, timer), dump the `SBSystemApertureWindow` subtree with OITInspector.
   - Decide how to put our own content in the Island: hook Apple's element providers (`SBSystemApertureStatusBarPillElementProvider` and friends) or draw our own overlay window.
   - Study Crescendo (see below). This decides the design of notifications and the queue.
4. **Queue/state controller, then Island-native notifications.**

### Needed from the owner
- The prefs plists (`Root`, `Color`, `Scale`, `Notifications`, `entry`) so slider defaults can be checked against the code defaults.
- Crescendo's source files (see below), or confirmation to continue from its README alone.
- A licensing decision on reusing anything from Crescendo.
- Measurements for iPhone 8 / 8 Plus (`iPhone10,1/10,2/10,4/10,5`) if they should get table entries: the Island Y and the banner Y.
- A decision on the OITI plist filter (see below).

### Crescendo notes (github.com/Yves000/Crescendo)
- Only the README could be read. GitHub blocks automated access to folder pages, and individual files need their URL pasted by the owner or the files uploaded. The files worth reading are `hooks/CRHooksDynamicIsland.x`, `CRPrivate.h`, `CRShared.m` and `CRPrefs.m`.
- **License: GPL-3.0.** Copying code would require GPL-compatible licensing and credit, and OITI's license is still undecided.
- Useful ideas from its README:
  - One dylib injected into SpringBoard and **MediaRemoteUI**. MediaRemoteUI renders the Island's expanded media player.
  - It builds its own volume slider from Apple's `MRU*` parts. That covers our "Volume Slider" idea.
  - A single predicate decides slider visibility, so there is one source of truth.
  - Live settings through Darwin notify-token state, with a preferences fallback.
  - Private headers verified against iOS 16, 17, 18 and 26 dumps.
  - Runtime version checks, so one build covers all versions.
  - `postinst` restarts only the affected process, not a full respring.
  - Uninstall removes everything the tweak wrote.
- **Plist filter:** `OITI.plist` currently filters on `com.apple.springboard` and `com.apple.UIKit`, so OITI already loads into MediaRemoteUI and every app. It is probably wasteful, but narrowing it (for example to the SpringBoard and MediaRemoteUI executables) should wait until Step 3 shows which processes we need.

## Licensing

- MIT for OITCore.
- OITI / OITS licensing TBD.
- OITG is still planned to use liquidass (GPL-3.0) once work on it begins.
- Attribution and licensing live in one project-wide `CREDITS.md` and one `LICENSES.md` rather than per-module sections.

## Toolchain

- **Primary:** Mac (macOS 27 beta, Xcode 27 beta). `TARGET` is pinned to `iphone:clang:16.5:16.0` to avoid Xcode 27's default iOS 27 SDK, and a `Preferences.tbd → Preferences` symlink was added to the SDK for bundle linking.
- **Also set up:** an Arch Linux PC (repo at `~/OITUI`, Theos at `~/theos` with `iPhoneOS16.5.sdk`, device paired over USB via libimobiledevice).
- **Packaging:** Theos with rootless packaging (`THEOS_PACKAGE_SCHEME=rootless`), deployed over SSH.
- **Deploy:** WiFi SSH to `192.168.4.89` stopped resolving in September 2026 (cause undiagnosed). The working method is USB through `iproxy`: run `iproxy 2222 22`, then build with `THEOS_DEVICE_IP=localhost THEOS_DEVICE_PORT=2222`.
- **Test device:** iPhone 8 Plus, jailbroken iOS 16.7.x.

## Module state

### OITCore
- All five source files built and confirmed working.
- Retain-cycle bug in `OITObserveDarwinNotification` fixed; respring listener centralized in OITCore's constructor.
- `floatForKey` accepts `NSString` values (fixes silently broken `PSEditTextCell` float fields).

### OITI
- OITIPrefs bundle complete: Root, Color, Scale and Notifications controllers.
- MobileGestalt corruption incident resolved with a breadcrumb-file backup/restore (`/var/mobile/Library/Preferences/OITIGestaltBackup.plist`) and an `OITIRestoreGestalt` helper tool run from a `prerm` script.
- `OITISafeScaleValue()` clamping prevents degenerate transform lockups; curtain-hide logic includes `scaleEnabled`.
- **Architecture (from code review):** OITI is not an Island renderer. `islandEnabled` writes `ArtworkDeviceSubType = 2556` into the MobileGestalt cache (backed up first, with a breadcrumb and a `prerm` restore helper), so iOS 16 builds its real SystemAperture. `Tweak.xm` then hooks `SBSystemApertureWindow` (position and scale), `SBBannerWindow` (notification banner position), `_SBSystemApertureMagiciansCurtainView` and `_SBGainMapView` (hide), `_SBSystemApertureContainerViewContentView` (background color), and `SBFTouchPassThroughView` (transparency and line hiding). Island content (music, timers) comes from Apple, not OITI. Ideas that need our own Island content (queue, notifications, progress bars, volume slider) therefore depend on the Step 3 research.
- **Known fragile spots:** `frame.origin` is written on a transformed window inside `layoutSubviews` (the pattern that tore down status bar views; fine so far); the `SBBannerWindow -frame` getter returns constants; the `subviews.count == 4` heuristic on `SBFTouchPassThroughView` may change between iOS versions.
- **Device table:** 17 models in `OITIDeviceProfiles.h`; seven are marked verified (iPhone X, XS, 11 Pro, 13 Pro, 13, 14), the rest are estimated.

### OITS
- All six elements implemented. **Repositioning works on-device** (confirmed by the author after the status bar layout change described below).
- Repositioning is transform-only (`CGAffineTransformMakeTranslation`) and applied exclusively from the `CADisplayLink` tick, never from system callbacks such as `setFrame:` or `layoutSubviews`. This resolved permanent view teardown.
- Offsets are converted into the parent's pre-scale coordinate space (`parentScale`), which matters whenever a layout stretches the foreground view.
- Discovery covers `_UIStaticBatteryView`, `_UIBatteryView` and a dedicated `_UIStatusBarCellularNetworkTypeView` path.
- Hide Elements (all six) restored and confirmed working.
- App Switcher / Control Center mirrored-view scoping guard is still missing (it was removed in an earlier revert) and is planned with extra caution. WiFi repositioning is best-effort.
- **Diagnostic build (written, not yet installed or tested on-device).** It contains the fixes in the next section plus extensive logging. Keep it on a branch until tested.

#### Fixes in the diagnostic build (untested)
- Clock detection now requires time-like text. The old "only string view among its siblings" rule mistook the "VZW Wi-Fi" carrier view for the clock whenever the real clock view was detached.
- The carrier-text heuristic no longer grabs the clock.
- Turning an element off sweeps every window and resets stale transforms. Status bar views are pooled and re-used, so a view that left the tracked set could stay displaced indefinitely.
- `sPrevious*Enabled` flags were never assigned, so reset-on-disable could never fire. They are now assigned.

## Status bar layout investigation (history)

- **Layout swap technique.** The third-party tweak [Little16](https://github.com/michaelmelita1/Little16) overrides `_UIStatusBarVisualProvider_iOS`'s `+class` to return a different Apple-native visual provider, so Apple's own layout code runs. Experiments:
  - `_UIStatusBarVisualProvider_RoundedPad_ForcedCellular`: works, looks more modern.
  - `_UIStatusBarVisualProvider_Phone`: infinite SpringBoard crash loop; ruled out.
  - `_UIStatusBarVisualProvider_Split1080`: no crash, but icons render scaled up and clipped.
- **Why Split1080 looked wrong.** `_UIStatusBarForegroundView` carries a uniform 1.104× transform (bounds 375 × 49.82, frame 414 × 55; 414 / 375 = 1.104). The layout is built for a 375 pt reference width and stretched to the 8 Plus's 414 pt, so child frames live in pre-scale space (the clock at x = -20.67, the battery at 382.67 and so off-screen). Any correction has to account for that scale.
- **Class findings under Split1080.** Battery is `_UIBatteryView`; network type is `_UIStatusBarCellularNetworkTypeView` (an icon, not a string view); cellular and WiFi use classes OITS already hooked; the clock is a generic `_UIStatusBarStringView` that shares its slot with the carrier text ("VZW Wi-Fi") and swaps with it.
- **Outcome.** After changing GesturesXV's Status Bar Style setting (it now shows "Legacy") and respringing, the status bar looks modern and correct: clock left, Dynamic Island centered, signal + LTE + battery percentage at right. The author attributes the change to GesturesXV. The exact mechanism has **not** been root-caused. The working hypothesis is that a forced layout class built for the wrong screen width was the problem. The planned check is to flip GesturesXV back to "iPhone X" and see whether the old layout returns.
- BarOnLandScape (a separate tweak that shows the status bar in landscape) was present in the old logs and was resetting the clock's transform every 150 ms. It is not part of OITUI or GesturesXV.

## Current status

- Status bar looks right; OITS repositioning works. OITS work is paused.
- OITI is the active module: Step 1 cleanup is written and untested; Steps 2–4 are planned (see "Where we left off").

## Open items

- OITS: test the diagnostic build's fixes when OITS work resumes; restore the scoping guard; revisit the cellular-to-WiFi disappearing symptom and the Control Center bug (needs `SpringBoard-*.ips` crash logs grepped for "oits") only if they still occur under the new layout.
- OITS: confirm the GesturesXV theory by flipping the style setting.
- OITI: acquire a Dynamic Island reference device for testing on real hardware; arm64e new-ABI limitation on Linux means DI builds may need GitHub Actions macOS runners.
- lldb debugging via XcodeRootDebug/USB was attempted unsuccessfully and remains an open goal.
- OITG: deferred.
- OITI: test the Step 1 files on-device, then start Step 2. Add logging first; OITI has none.
- OITI: add table entries for iPhone 8 / 8 Plus once measured.
