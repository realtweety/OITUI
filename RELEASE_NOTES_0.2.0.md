# OITUI 0.2.0

OITUI 0.2.0 brings the Island notification stack, more responsive OITI Settings controls, and an optional Hello startup animation prototype.

## OITI

- **Island Notifications:** show notification banners as elements in the Dynamic Island, with controls for style, display duration, message lines, roundness, stock-banner visibility, and optional haptics.
- **Notification stack:** keep up to four notifications visible. In Expanded or Wide style, the newest notice is the main item and older notices appear as separate compact cards. In Compact style, all notices are compact. New notices evict the oldest. This feature remains experimental and Settings clearly warns that it is usable but unpolished. It can be turned off independently.
- **Startup Animation prototype:** an off-by-default setting plays the bundled six-second Hello animation after respring or userspace reboot, once the device is unlocked on the Home Screen. It has a five-minute cooldown. Charging activity waits until playback ends; calls and other Island activity can interrupt it. The supplied animation asset’s creator permits unrestricted reuse.
- **Settings responsiveness:** sliders, text fields, switches, choice controls and reset actions respond more reliably.

## Installation

Requires a rootless iOS 16 jailbreak and OITCore. Install the OITCore and OITI `.deb` packages together, with OITCore installed first if installing them separately. This release was tested on an iPhone 8 Plus running iOS 16.7.16 with Dopamine 3.

## Known limitations

- The notification stack is experimental and unpolished. The stack and this release have only been tested on the owner’s iPhone 8 Plus running iOS 16.7.16; other iOS versions and real Dynamic Island hardware have not been verified.
- Compact and Wide notification layouts are experimental.
- Notifications delivered only to the Lock Screen do not pass through the banner presentation hook.
- The Hello animation is labelled as a prototype and stays off by default.
- OITS is not included in this release.

See `COMMANDS.md` for diagnostic and recovery steps. Island notification titles and message snippets may appear in diagnostic logs when verbose diagnostics are enabled; review logs before sharing them.

OITI is based on VisibleIsland by ethxnn88, used with permission. OITI's Settings pages are adapted from Liquid (Gl)Ass by Winaviation under CC BY-NC 4.0; changes were made for OITUI and the upstream author does not endorse OITUI. See the license text in `Third Party Licenses/LIQUIDASS-LICENSE.txt` and the [upstream repository](https://github.com/winaviation-tweaks/liquidass).
