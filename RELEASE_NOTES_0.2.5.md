# OITUI 0.2.5

OITUI 0.2.5 is a big update to Insula since 0.2.0: download progress in the Island, Apple Mode, live appearance settings, safer recovery, and a new name. The source code was also reorganised into modules; the code was moved without changing it.

## Insula (OITI)

- **Download Progress (off by default):** shows a download in the Island, with a Minimal and a Detailed look, an App Store source that follows installs and updates by percentage, a red Cancelled state, a check-mark completion animation (Minimal look) and a fake test download in Settings. Browsers are not supported yet.
- **Apple Mode:** one switch that turns every Island customization off at once so you can see how the stock Island behaves. It keeps Enable Dynamic Island, the built-in position and notification fixes, the Status Bar Layout setting and safe mode.
- **Live settings:** custom colour, opacity, outline hiding and banner offset apply without a respring.
- **Relative scaling:** the Width (X) and Height (Y) sliders on the Scale page (new keys, nothing to migrate) now scale relative to Apple's own Island size.
- **Safe mode you can see:** if SpringBoard restarts several times in a short window, Insula switches its tweaks off by itself. Settings shows a banner with the reason and a **Clear Safe Mode & Respring** button; a respring from Settings does not count towards the loop guard.
- **Expanded Island crash recovery:** after a SpringBoard restart, Island notifications and the startup animation stay off for two minutes so a re-delivered notification cannot rebuild the element that crashed.
- **Device awareness:** a table of 17 iPhone models, each marked verified or estimated, and native-provider learning for the status bar.
- **Settings fixes:** a crash when picking some options is fixed, the opacity slider is labelled correctly, and the installed version shows at the bottom of the main page.

## Names

Tellus (OITUI), Insula (OITI) and Litus (OITS) are the display names in Sileo and Settings. Package IDs, files, logs and preference keys keep the OIT names, so your settings carry over.

## Under the hood

`Tweak.xm` was about 5,850 lines and is now about 270: the code lives in modules (Diagnostics, Download Progress, Island Size, Island Notifications, Startup, Status Bar, Safety and a shared core). Each step was moved without changes and checked on a device.

## Installation

Requires a rootless iOS 16 jailbreak and OITCore. Install the OITCore and Insula `.deb` packages together, with OITCore installed first if installing them separately. OITCore stays at 0.1.0. This release was tested on an iPhone 8 Plus running iOS 16.7.16 with Dopamine 3.

## Known limitations

- Download Progress follows App Store installs only; browsers and TestFlight are not covered yet.
- The notification stack is still experimental and unpolished; the limitations listed for 0.2.0 still apply.
- Only the owner's iPhone 8 Plus on iOS 16.7.16 has been tested; other iOS versions and real Dynamic Island hardware have not been verified.
- Litus (OITS) is not included in this release.

Insula is based on VisibleIsland by ethxnn88, used with permission. Its Settings pages are adapted from Liquid (Gl)Ass by Winaviation under CC BY-NC 4.0; changes were made for OITUI and the upstream author does not endorse OITUI. See `Third Party Licenses/LIQUIDASS-LICENSE.txt` and the [upstream repository](https://github.com/winaviation-tweaks/liquidass).
