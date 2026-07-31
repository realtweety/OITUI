# OITUI Feature Ideas

Running list of ideas for OITI/OITS/OITG, gathered from brainstorming (including a
ChatGPT session) and our own planning. Nothing here is committed -- this is a menu,
not a roadmap. Update freely as priorities shift.

## Up Next (once OITS is functional)

- **Island-native notifications** (Grey's idea): instead of the stock banner, notifications
  expand the Island to show the app icon, app name, and a shortened message. OITI already
  hooks `SBBannerWindow` for repositioning (`notificationFix`/`notEnabled`), so this is a
  content-routing change on top of code we've already proven stable, not new territory.
  Open questions when we get here: truncation rules, and what happens when a second
  notification arrives while one is still showing (see "Island Stacks" / queue idea below).

## Good, well-scoped, worth doing eventually

- **Modular architecture**: split `Tweak.xm` into `Modules/Music`, `Modules/Phone`, etc.
  instead of one growing file. Already the direction OITI's headed.
- **Device awareness**: extend the existing per-device offset table (`fixEnabled`) rather
  than treating this as new.
- **Apple Mode vs Enhanced Mode**: simple toggle, conservative default, low risk.
- **Developer/debug overlay**: FPS, blur passes, render time. OITG already has real
  scaffolding for this (`LGProfileBegin`/`LGProfileEnd`, the all-day profiler) -- extend
  that pattern rather than building new.
- **Crash recovery for an expanded Island state**: small, concrete, testable.
- **Island Stacks / queue**: multiple things (music, timer, download) don't fight for the
  same space -- swipeable or queued instead of clobbering each other.
- **Context awareness**: Island content adapts to foreground app (Maps -> nav controls,
  Spotify -> media controls). Natural extension of app-state hooking we already do.
- **Universal progress bars**: any app/tweak can expose a progress value the Island renders
  generically. Precursor to a real plugin API, but useful even as a single hardcoded case first.

## OITG integration

Plan: once OITS is stable, one small contained experiment -- wire `LGSharedGlassView` into
just the *expanded* Island state (not the always-visible idle pill), and actually measure
cost on the 8 Plus (A11) before deciding how far this goes. `LGSharedGlassView` is already
generic (reused across liquidass's back button, sliders, switches), so this isn't
architecturally weird -- but none of that usage is "always on screen," which is a very
different battery/perf profile than a transient banner or menu.

## Interesting, but not yet -- needs its own design pass first

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

## Explicitly deferred -- different category of project, not "later feature work"

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
from brainstorm sessions -- that's marketing language, not an engineering target. OITG's
renderer does real Metal work per surface; set honest perf budgets once something is
actually rendering on-device, not before.

## Confirmed via OITInspector dump (2026-07-16)

- `SBSystemApertureStatusBarPillElementProvider` / `SBSystemApertureStatusBarPillElement` exist
  as real classes on-device. These appear to be Apple's own connective tissue between the status
  bar layout system and the Dynamic Island -- worth investigating directly if we ever pursue the
  "status bar flows into the Island" idea for real.
- `SBMainDisplaySceneLayoutStatusBarView` is confirmed live at runtime (caught in a real window
  dump), full-screen, zero UIView-based children -- status bar content is very likely rendered via
  a private/cross-process mechanism, not addressable UIKit subviews. OITS will likely need to
  manipulate this container as a whole (frame/transform) rather than targeting an individual clock
  label.

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
- **OITG**: TBD -- something conveying glass/refraction/liquid material.
  Maybe a droplet or refracted-light motif, playing off "Liquid Glass."
- **OITUI (whole project)**: TBD -- needs to feel like it ties the family
  together once the individual module icons exist. Revisit after the others
  are settled so it doesn't clash.
