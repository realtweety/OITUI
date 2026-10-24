# OITUI Ideas



## OITI: current state and next candidates

- **Island Notifications (0.2.0; stack tested on-device).** The owner tested bursts of four on an iPhone 8 Plus running iOS 16.7.16. In Expanded/Wide style, the newest notice is the main expanded item and older ones appear as separate rounded compact cards in its secondary content; they still share the system's outer expanded Island card. Compact style keeps all notices compact. Capacity is four; new notices evict the oldest. Timeout restarts on demotion to compact and promotion, and items can be dismissed individually. Lock-screen-only deliveries still bypass the banner path. The stack is usable but explicitly experimental and not polished.
- **Settings controls (device-tested).** The owner reports the controls feel more responsive after reducing slider preference-write frequency, saving text fields on editing end, updating picker labels in place, making switch labels tappable, and refreshing custom controls after reset actions.
- **Dedicated toggles:** `islandNotificationsEnabled` controls custom Island notifications (default off); `islandNotificationStackEnabled` controls multi-notice stacking (default on to preserve existing behavior). Settings labels and warning text call out that stacking is experimental and usable but unpolished.
- **Remaining notification work:** Verify Compact/Wide and real notification paths broadly, confirm timeout behavior over longer intervals, test on real Dynamic Island hardware and other iOS 16 builds. Keep the current card layout unless owner asks to revisit it. Progress bars are a possible later addition.
- **Hello Startup Animation (0.2.0).** The off-by-default toggle waits until the device is unlocked and SpringBoard is active on the Home Screen, checks a persistent five-minute cooldown, and shows an expanded Island element. The owner confirmed the Home Screen gate, video sizing, cooldown, uninstall, toggle and interruption behavior on-device. The AVPlayer-backed view plays the supplied SVG-derived clip once without audio and removes the Island element when playback ends or fails. While it plays, charging activity is kept registered but placed behind the startup animation; calls and other Island activity take priority. The bundled H.264 clip is 1280×720, six seconds, white on black.
- **Volume slider:** deferred after an initial implementation was removed because it did not work and did not seem broadly useful.
- **Polish list** (owner chose to defer): live color, opacity and banner offset (done on `experiments`, build `OITI-exp-2026-10-21-a`, untested on-device); banner position at extreme Island sizes; make the X/Y scale relative to Apple's own size (done on `experiments`, build `OITI-exp-2026-10-21-b`: new keys `RelativeScaleX` / `RelativeScaleY`, no migration, untested on-device); maybe lower the Island Height slider minimum (around 0.6 is where 22 pt artwork stops fitting, untested).
- **Per-app exclude list for Island Notifications.** Deferred until someone asks for it (keep Phone or Timer on the stock banner, for example).
- **OITS** is parked: revert or adapt to the `_UIStatusBarProvider_DynamicSplit` layout class, rebuild the lost diagnostic fixes, restore the scoping guard.

## Things I Think Would Be Nice

- **Modular architecture**: split `Tweak.xm` into modules (`Modules/Music`, `Modules/Phone`, etc.)
  instead of one growing file. **Status:** no modules exist yet. Step 1 added a shared device table
  (`OITIDeviceProfiles.h`); real modules make sense once the content-injection research is done.
- **Device awareness**: done as a table in `OITIDeviceProfiles.h` (17 models, each marked verified or estimated).
  Remaining: entries for iPhone 8 / 8 Plus (needs on-device measurement) and more devices.
- **Apple Mode vs Enhanced Mode**: done on `experiments` (build `OITI-exp-2026-10-21-b`, untested on-device) as a single `appleMode` switch that forces every Island customization off and keeps Enable Dynamic Island, the built-in position and notification fixes, the Status Bar Layout setting and safe mode.
- **Developer/debug overlay**: FPS, render time, active Island state, and other useful runtime diagnostics. Keep it focused on information that can actually be measured on-device.
- **Crash recovery for an expanded Island state**: done on `experiments` (build `OITI-exp-2026-10-21-c`, untested on-device) as a live-element breadcrumb file plus a 120 s window at the next launch in which Island notifications and the startup animation stay off. Nothing about the expanded Island is persisted across a SpringBoard restart, so the real risk was a re-delivered notification rebuilding the element that crashed.
- **Island Stacks / queue**: multiple things (music, timer, download) don't fight for the
  same space -- swipeable or queued instead of clobbering each other. Needs a content mechanism first (Step 3 research).
- **Context awareness**: Island content adapts to foreground app (Maps -> nav controls,
  Spotify -> media controls). Needs a content mechanism first.
- **Universal progress bars**: any app/tweak can expose a progress value the Island renders
  generically. Precursor to a real plugin API. First use: **download progress** (stage 1 built on `experiments`, build
  `OITI-exp-2026-10-21-d`, untested on-device, fake download only). Owner's decisions: downloads first; App Store and Safari
  as the first real targets, Chrome and Arc later (they need hooks inside each app); return to idle by MB downloaded and/or
  seconds on screen, user-chosen; off by default; a fake download for testing. Timers and other sources can use the same
  tracker later.
- **OITUI App**: Make a whole new app specifically for customizing OITUI tweaks like OITI and OITS. I would probably add in some sort of live preview to show the user what their settings would look like before they apply everything. It would essentially just move OITUI tweak customization from Settings to a dedicated app
- **Volume Slider**: It might be a cool idea to try and move the volume slider into the dynamic island somehow, maybe do the same thing with other sliders and indicators and whatnot.
  **Note:** the tweak Crescendo (github.com/Yves000/Crescendo, GPL-3.0) already does this for the expanded media player by
  building a slider from Apple's own `MRU*` parts inside MediaRemoteUI. Worth studying (and checking for conflicts with OITI) before building our own.

## Decent Ideas

- **Clipboard history/pinning/OCR**
- **Quick calculator / unit / currency conversion**
- **Translation popup**
- **Universal timer stack, stopwatch controls**
- **Volume mixer, brightness slider, flashlight controls in-Island**
- **Detailed battery stats** (current draw, watts, temp, estimate)
- **Bluetooth/WiFi/VPN quick switches**
- **Live CPU/RAM/FPS/network monitors**
- **Package installer, respring menu in-Island**
- **Notification snoozing**
- **Command palette / Island search**
- **Macros** ("Good Night" -> multiple actions at once)
- **Pin/favorite specific Island cards**
- **Smart/predictive suggestions** (AirPods connect -> show ANC controls)
- **Automation rules** ("if X then Y")
- **Themes / material profiles / per-app accent colors**
- **Notification timeline / scrub-back history**

## Entirely Different Things and Projects

- **Plugin marketplace / public SDK for other tweak devs**: assumes external adoption that
  doesn't exist yet. Build after OITI itself is solid, not before.
- **Anything needing live third-party network calls** (translation APIs, currency, "AI
  quick actions"): different risk/complexity class than anything built so far -- API keys,
  rate limits, offline failure modes. Not until the core system is proven.
- **"Island Studio" companion app**: a second, separate piece of software with its own
  toolchain. Not a feature -- a different project.
- **Merging OITS and OITI into one unified status/event engine**: genuinely interesting
  long-term direction (shared module system, status bar flowing into the Island), but
  premature to design before either one individually works.

## Notes on hype language

Ignore any "120fps guaranteed / zero dropped frames / immeasurable battery impact" framing
from brainstorm sessions -- that's marketing language, not an engineering target. Any renderer
that does real rendering or compositing work should have honest performance budgets set only after
on-device measurement, not before.

## Confirmed via OITInspector dump (2026-07-16)

- `SBSystemApertureStatusBarPillElementProvider` / `SBSystemApertureStatusBarPillElement` exist
  as real classes on-device. These appear to be Apple's own connective tissue between the status
  bar layout system and the Dynamic Island -- worth investigating directly if we ever pursue the
  "status bar flows into the Island" idea for real.
- **Correction (Oct 2026):** the status bar content *is* ordinary UIKit subviews: `_UIStatusBar` -> `_UIStatusBarForegroundView` ->
  per-element views (`_UIStatusBarStringView`, `_UIBatteryView`, wifi and cellular signal views, network type view). OITS already
  moves individual elements. `SBMainDisplaySceneLayoutStatusBarView` is only a full-screen container with no UIKit children.
  OITInspector can't enumerate the persistent `UIStatusBarWindow`; use FLEX or the OITS diagnostic dump (`DIAGNOSTICS.md`).

## Confirmed via dumps (Oct 2026)

- The Island can be resized without scaling its content: scale `SBUISystemApertureLayoutMetrics -sensorRegionSize` (the root input). Done and released in v0.1.0 as the Island Size sliders.
- Apple has a content element model (`SBSystemApertureProvidedContentElement`, `SBUISystemApertureCustomContentProvider`, `SAUISystemApertureManager`, `SBSystemApertureElementAuthority`) that may let OITI add its own elements as real Island elements. This replaces the "own overlay window" idea as the default plan.

## Confirmed via code review (Oct 2026)

- OITI is a positioning/appearance shim over Apple's real Dynamic Island. `islandEnabled` spoofs `ArtworkDeviceSubType` (2556) so
  iOS builds SystemAperture; `Tweak.xm` hooks `SBSystemApertureWindow`, `SBBannerWindow` and a few appearance views. Island content
  (music, timers) is Apple's. The Island's expanded media player is rendered by the **MediaRemoteUI** process (per Crescendo's README).
- Next research step (done in October 2026): the element route was chosen and works. Notes: `LEARNINGS.md`, "Island elements".

## Infrastructure ideas (from the OITI review and Crescendo)

- **Split `Tweak.xm` into module folders** (owner's idea, to do after the current testing round): for example `OITI/Download Progress/`, `OITI/Resizing/`, `OITI/Notifications/`, `OITI/Startup/`, with a small shared core for logging, preferences and the element machinery. Folder names with spaces are fine for Theos but a nuisance in shell commands, so `DownloadProgress/` is probably better. The work is mostly moving code without changing behavior, which makes it risky in one big step: do it one module at a time with a build and a short device check after each, starting with the most self-contained one (the download tracker and its views, which only touch the element presenter through two calls). The file list lives in `OITI/Makefile` (`OITI_FILES`), and Logos `%hook` groups can sit in `.xm` files in any folder.

- **Respring-loop safe mode**: auto-disable OITI features after repeated respring cycles in a short window.
- **Startup self-check** for the MobileGestalt spoof: log when `islandEnabled` is on but the cache no longer holds the spoofed value.
- **Shared logging in OITCore** (`OITLog`): async, rate-limited, state-change logging, reused from the OITS diagnostic build.
- **Live settings** over a Darwin notify-token state with a preferences fallback, so most changes need no respring.
- **Clean-uninstall guarantee**: removing a package removes everything it wrote (already true for the MobileGestalt value via `prerm`).
- **Contributor hygiene**: issue templates and a short CONTRIBUTING file.

## Icon concepts (not yet made, no urgency)

- **OITI**: Capsule/pill silhouette (the Island's actual shape) with something
  happening subtly *inside* it -- a small glass refraction highlight, or the
  pill mid-morph into a slightly different shape. Dark background, single
  accent color, restrained rather than busy.
- **OITS**: Thin status-bar-shaped bar across the top of the icon, split
  left/right with a small gap in the middle (echoing the iOS 26/27 layout
  target) -- clock glyph on one side, signal/battery glyphs on the other.
- **OITCore**: Not user-facing, so probably skip a "cute" icon -- simple
  geometric mark (hexagon/gear) is enough.
- **OITUI (whole project)**: TBD -- needs to feel like it ties the family
  together once the individual module icons exist. Revisit after the others
  are settled so it doesn't clash.
