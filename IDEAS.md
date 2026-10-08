# OITUI Ideas



## Up Next (OITI)

- **Island-native notifications** Instead of the stock banner, notifications
  expand the Island to show the app icon, app name, and a shortened message. Open questions when we get here: truncation rules, and what happens when a second
  notification arrives while one is still showing (see "Island Stacks" / queue idea below).
  **Status:** blocked on research. OITI currently only repositions and restyles Apple's own Island; it has no way to put
  its own content in it yet (see "Confirmed via code review" below). Plan: OITI Steps 1-4 in `OVERVIEW.md`.

## Things I Think Would Be Nice

- **Modular architecture**: split `Tweak.xm` into modules (`Modules/Music`, `Modules/Phone`, etc.)
  instead of one growing file. **Status:** no modules exist yet. Step 1 added a shared device table
  (`OITIDeviceProfiles.h`); real modules make sense once the content-injection research is done.
- **Device awareness**: done as a table in `OITIDeviceProfiles.h` (17 models, each marked verified or estimated).
  Remaining: entries for iPhone 8 / 8 Plus (needs on-device measurement) and more devices.
- **Apple Mode vs Enhanced Mode**: simple toggle, conservative default, low risk.
- **Developer/debug overlay**: FPS, render time, active Island state, and other useful runtime diagnostics. Keep it focused on information that can actually be measured on-device.
- **Crash recovery for an expanded Island state**: small, concrete, testable.
- **Island Stacks / queue**: multiple things (music, timer, download) don't fight for the
  same space -- swipeable or queued instead of clobbering each other. Needs a content mechanism first (Step 3 research).
- **Context awareness**: Island content adapts to foreground app (Maps -> nav controls,
  Spotify -> media controls). Needs a content mechanism first.
- **Universal progress bars**: any app/tweak can expose a progress value the Island renders
  generically. Precursor to a real plugin API. Needs a content mechanism first.
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

## Confirmed via code review (Oct 2026)

- OITI is a positioning/appearance shim over Apple's real Dynamic Island. `islandEnabled` spoofs `ArtworkDeviceSubType` (2556) so
  iOS builds SystemAperture; `Tweak.xm` hooks `SBSystemApertureWindow`, `SBBannerWindow` and a few appearance views. Island content
  (music, timers) is Apple's. The Island's expanded media player is rendered by the **MediaRemoteUI** process (per Crescendo's README).
- Next research step: dump the `SBSystemApertureWindow` subtree with OITInspector while a stock element is active, then decide between
  hooking Apple's element providers and drawing our own overlay.

## Infrastructure ideas (from the OITI review and Crescendo)

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
