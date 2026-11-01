# OITUI 0.2.5

OITUI 0.2.5 is a maintenance release. Behavior is unchanged from 0.2.0; the source code was reorganised and the project now uses its Latin display names.

## What changed

- **Display names:** the project is Tellus, the Dynamic Island module is Insula, and the status bar module is Litus. Settings, package names and the Settings pages use the new names. Bundle identifiers and preference keys are unchanged, so your settings carry over.
- **Internal restructure ("The Great Split"):** the single 5,800-line `Tweak.xm` was split into modules (Diagnostics, Download Progress, Island Size, Island Notifications, Startup, Status Bar, Safety and a shared core). Code was moved without changing it; the device checks after each step found no difference in behavior.

## Installation

Requires a rootless iOS 16 jailbreak and OITCore. Install the OITCore and Insula `.deb` packages together, with OITCore installed first if installing them separately. OITCore stays at 0.1.0. This release was tested on an iPhone 8 Plus running iOS 16.7.16 with Dopamine 3.

## Known limitations

- The notification stack is still experimental and unpolished; the limitations listed for 0.2.0 still apply.
- Only the owner's iPhone 8 Plus on iOS 16.7.16 has been tested; other iOS versions and real Dynamic Island hardware have not been verified.
- OITS (Litus) is not included in this release.

Insula is based on VisibleIsland by ethxnn88, used with permission. Its Settings pages are adapted from Liquid (Gl)Ass by Winaviation under CC BY-NC 4.0; changes were made for OITUI and the upstream author does not endorse OITUI. See `Third Party Licenses/LIQUIDASS-LICENSE.txt` and the [upstream repository](https://github.com/winaviation-tweaks/liquidass).
