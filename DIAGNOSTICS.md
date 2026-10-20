# OITS Diagnostics

The OITS diagnostic build adds extensive logging for status bar problems. It is **not yet tested on-device** and should live on a branch (for example `oits-diag`) until it has been. Repositioning behavior is unchanged from the normal build apart from the fixes listed in `OVERVIEW.md`.

## Where things are

| Item | Location |
| --- | --- |
| Log file | `/tmp/OITSDebug.log` (rotates at about 6 MB to `/tmp/OITSDebug.log.1`) |
| Dump trigger | `touch /tmp/OITSDump.trigger` (detected by modification time within about a second) |
| Dump via Darwin notification | `com.wilburt.oits/DumpState` |
| Prefs keys | `DiagnosticsEnabled` (bool, default on), `DiagnosticsLevel` (0–2, **default 0**) |

Levels: 0 = legacy lines only; 1 = events, state changes and heartbeat; 2 = adds every hooked call (rate limited) and a filtered tap on system notifications.

**Diagnostics are off by default.** At level 0 OITS writes only its few legacy, session and preference lines and the `MAINSTALL` warning; there is no heartbeat, visibility watchdog, baseline dump or notification tap. To collect diagnostics, raise the level on the phone and respring:

```
defaults write com.wilburt.oits.prefs DiagnosticsLevel -int 2
sbreload
```

Set it back with `-int 0` (or `defaults delete com.wilburt.oits.prefs DiagnosticsLevel`) when you are done.

Logging is asynchronous and rate limited, so it should not stall SpringBoard. Deleting the log while running is safe; a fresh file is started.

## Log line format

`MM-DD HH:MM:SS.mmm +seconds-since-load #sequence M|B tNNN [TAG] message`

`M` or `B` is main or background thread; `tNNN` is the enforcer tick count.

## Tags

| Tag | Meaning |
| --- | --- |
| `SESSION` | Start and ready lines with build tag, PID, OS and device. More than one `START` in a file means SpringBoard restarted. |
| `PREF` | Preference reload with every value, marked CHANGED or no change |
| `TRACK` | A view started being tracked, how it was found, and its natural X. `UNTRACK` lines appear here too |
| `SKIP` | A candidate view was not tracked, with the reason (logged once per view) |
| `DEAD` | A tracked view left its window, with how long it was tracked |
| `APPLY` | OITS wrote a transform or hidden flag (old to new, with every intermediate value) |
| `REFUSED` | A computed delta was rejected as implausible |
| `STATE` | A tracked view's hidden, alpha, transform, frame, superview, window or text changed |
| `VIS` | A view's visibility changed, with the reason (`hidden@Class`, `alpha~0@Class`, `no-window`, `offscreen`, `partial NN%`) |
| `SYS-SET` | Something other than OITS changed hidden, alpha or transform. Includes `third-party=[...]` dylibs on the stack and a capped stack trace |
| `MOVE` / `REMOVE` | `didMoveToWindow` and `removeFromSuperview`, with stack for tracked views |
| `SETFRAME` / `LAYOUT` / `SUBVIEW` | Level 2 detail on frame writes, foreground view layout, and subview add/remove |
| `DISCOVER` | Tracked-view counts changed, with the window list |
| `HB` | Heartbeat every 3 seconds: enforcer state, tracked counts, per-view position and visibility |
| `WARN` | An element is enabled but nothing is tracked |
| `TICKGAP` / `TICKSLOW` / `MAINSTALL` | Display link gaps, slow ticks, and main-thread stalls |
| `ENFORCER` | Display link started or stopped |
| `DUMP` | Hierarchy dumps (see below) |
| `NOTIF` / `DARWIN` | Filtered system notifications correlated with events |

## Hierarchy dumps

A dump lists every window and then, for each status-bar-related subtree, one line per view with its label, frame, transform, alpha, text and visibility, plus ancestor chains. It also prints a `PROVIDER` line naming each `_UIStatusBar`'s visual provider class together with screen bounds and scale (build `2026-10-02-c` and later).

Dumps happen automatically 2 seconds after SpringBoard is ready (a baseline), the first 8 times a status bar view becomes invisible, and on demand.

## Commands

On the phone. Do not paste commands with trailing comments; zsh passes them as arguments.

```
rm -f /tmp/OITSDebug.log /tmp/OITSDebug.log.1
sbreload
```

After the respring, in a new SSH shell:

```
mark() { echo "$(date '+%m-%d %H:%M:%S') [MARK] $*" >> /tmp/OITSDebug.log; }
mark START
touch /tmp/OITSDump.trigger
```

Reading results:

```
grep -c SESSION /tmp/OITSDebug.log
grep -E "MARK|VIS|SYS-SET|REMOVE|DEAD" /tmp/OITSDebug.log | tail -80
grep DUMP /tmp/OITSDebug.log | tail -300
grep -E "REFUSED|APPLY" /tmp/OITSDebug.log | tail -40
grep -E "TICKGAP|TICKSLOW|MAINSTALL" /tmp/OITSDebug.log | tail -20
grep -E "SESSION|PROVIDER" /tmp/OITSDebug.log
ls -t /var/mobile/Library/Logs/CrashReporter/SpringBoard-*.ips | head -3
```

On the Mac, with the `iproxy 2222 22` tunnel running:

```
scp -P 2222 root@localhost:/tmp/OITSDebug.log ~/Desktop/OITSDebug.log
```

## Reading results

| Around the symptom | Likely meaning |
| --- | --- |
| `SYS-SET ... by=SYSTEM` | The system, or the tweak named in `third-party=[...]`, changed the view. The stack shows who |
| `REMOVE` or `DEAD` | The view was torn down; check whether a `TRACK` line re-tracked its replacement |
| `VIS ... hidden@X` / `alpha~0@X` | An ancestor `X` is hiding it, not the view itself |
| `VIS ... text=""` or a transparent `textColor` | The text went blank or clear |
| `REFUSED`, or a huge `APPLY` delta with `parentScale` far from the layout's scale | The scale math is wrong for that instance |
| `TRACK ... "VZW Wi-Fi"` labelled clock | Clock mis-detection (fixed in the diagnostic build) |
| `WARN ... ENABLED but nothing is tracked` | Discovery is failing for that element |
| `TICKGAP` / `MAINSTALL` | The main thread was blocked, or the display link paused (screen off) |

## Overhead

Ticks that run discovery and the visibility watchdog together (every 30 ticks) measured about 4 ms in testing, and app transitions measured 5–13 ms. That is acceptable for diagnosis but not for a release build; set `DiagnosticsEnabled` off or ship without the diagnostic build for daily use.

## OITI diagnostics

OITI has the same kind of logging, built on `OITLogger` from OITCore.

| Item | Location |
| --- | --- |
| Log file | `/tmp/OITIDebug.log` (rotates at about 6 MB to `/tmp/OITIDebug.log.1`) |
| Prefs-bundle log (MobileGestalt writes) | `/tmp/OITIPrefsDebug.log` |
| Dump trigger | `touch /tmp/OITIDump.trigger`, or Darwin notification `com.wilburt.oiti/Dump` (needs level 1 or higher) |
| Class query | put class names, one per line, in `/tmp/OITIClassQuery.txt` before triggering a dump |
| Prefs keys | `DiagnosticsEnabled` (bool, default on), `DiagnosticsLevel` (0–2, **default 0**) |

At level 0 OITI writes only `SESSION`, `GUARD`, `SAFE`, `CHECK` and a few `NOTIF` / `ELEMENT` lines (the two install lines and any failure, see below), about a dozen per boot, and that includes every warning (respring-loop guard, safe mode, MobileGestalt spoof self-check). It runs no polling timer and tracks no windows. Level 1 adds events and state changes (`PREF`, `ISLAND`, `CURTAIN`, `COLOR`, `BANNER`, `GAINMAP`, `TOUCHPASS`), starts the trigger-file poll and takes one baseline dump after the Island first lays out. The aperture research build also logs rate-limited `APERTURE` element-construction and manager-registration events at level 1. Level 2 adds rate-limited per-call lines (`LAYOUT`).

```
defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 1
sbreload
```

Safe mode: after 5 SpringBoard launches within 120 s OITI stops installing its hooks until `/var/mobile/Library/Preferences/OITISafeMode.plist` is removed (or Darwin notification `com.wilburt.oiti/ClearSafeMode`), then respring. Installing or upgrading the package clears it.

### OITI dump contents

A dump (`touch /tmp/OITIDump.trigger`, or the `dumpstate` helper in `COMMANDS.md`) writes `DUMP` lines for: the environment and preference snapshot (`ENV`, `PREFS`), a window overview (`WINDOWS`), a **`METRICS` section** (every no-argument getter on `SBUISystemApertureLayoutMetrics` and its class, the multiplier in use, and the raw value Apple returned to the hook), each tracked Island window's view and view-controller tree (`WINDOW`, `VC`, `TREE`), every loaded class with "aperture" in its name (`CLASSES`), and loaded protocols with "aperture" in their name (`PROTOCOL`). `RESEARCH` lines report actual method encodings on this device for the element/provider constructors and registration APIs. This read-only ABI check comes before adding event hooks against private methods. Classes named in `/tmp/OITIClassQuery.txt` are described under `CLASSQ` (superclass chain, protocols, ivars, methods). Query at most 5 classes per dump so the logger's backlog limit (4000 lines) does not drop lines.

Useful greps on the phone: `grep METRICS /tmp/OITIDebug.log`, `grep CLASSQ /tmp/OITIDebug.log`, `grep MARK /tmp/OITIDebug.log`. The exact commands, per-state labels (`idle-home`, `lockscreen`, `spotify-collapsed`, `spotify-expanded`, `timer-compact`, ...) and class batches are in `COMMANDS.md`, sections 5 and 6.

A normal install runs at level 0, so none of this is active until `DiagnosticsLevel` is raised.

### OITI status bar layout and provider log (STATUSBAR)

Chases the red status bar titled `rdar:45025538` that some notch iPhones show while the Island spoof is on. With the Island on, UIKit's `+[_UIStatusBarVisualProvider_iOS visualProviderSubclassForScreen:visualProviderInfo:]` returned `nil` on an iPhone 13 mini and iOS fell back to its placeholder. OITI hooks that method (always calling `%orig`) and can return the device's native provider.

Level 0:

- `CHOICE`: what UIKit returned, the screen's native bounds, the Island state, the Status Bar Layout setting, the decision taken and what OITI returned. One line per distinct combination, at most 16.

Level 1 (boot report 4 seconds after SpringBoard starts, and with every dump):

- `BEGIN` / `END`, `SCREEN` (bounds, native bounds, scale, native scale), `TABLE` (device table entry), `OVERRIDE` (`UIStatusBarVisualProviderClassName` in `com.apple.UIKit`, if any), `LAYOUT` (the setting).
- `PROVIDER`: every loaded class named `_UIStatusBar*Provider*` with its superclass, up to 60.
- `LIVE`: for each `_UIStatusBar`, from `-_prepareVisualProviderIfNeeded`: the provider class it has, its class name, target screen and window. At most 24.

Status Bar Layout (key `StatusBarLayout`, picker at the bottom of the settings page), only while the Island is on:

- `auto` (default): on a notch iPhone in the device table, return its native provider when UIKit chose nothing or `_UIStatusBarVisualProvider_Fallback`, or, for the 828 and 1080 pixel screens, when UIKit chose anything else. Everything else is left alone.
- `off`: never change UIKit's answer.
- a `_UIStatusBarVisualProvider_*` class name: return that class.

Native providers read from a device's own log (Island off): `iPhone14,4` (13 mini) uses `_UIStatusBarVisualProvider_Split1080_Wide`. Other devices use a guess by native pixel width until a log is available.

Steps and commands: `COMMANDS.md`, section 12.

### OITI Island Notifications and Startup Animation (NOTIF, ELEMENT and HELLO, 0.2.0)

Two tags cover the feature. `NOTIF` is the banner hook and the stock banner. `ELEMENT` is the Island element's life. At level 0 only the install lines and failures are written (so a bug report always has them); everything else needs level 1.

Level 0:

- `NOTIF banner hook installed on -[SBNotificationBannerDestination postNotificationRequest:] (encoding v24@0:8@16)`, or `NOTIF banner hook NOT installed ...` followed by `CANDIDATES` lines listing the related methods (the selector differs between iOS versions).
- `ELEMENT promotion guard installed ...`, or `... NOT installed` with the reason.
- Failures: `no SAUISystemApertureManager seen yet`, `missing class`, `creation failed`, `exception while creating/registering the element`, `could not dismiss the element`, `could not open <bundle>`, `GESTURES: no host view found`, `element creation is off until the next respring`.
- `ELEMENT GUARD caught <exception>: <reason>` with the first ten stack symbols, `GUARD element` and `GUARD parts` lines for every registered element, and `dismissed element ...`. This is the promotion guard doing its job: an exception inside `-[SAUISystemApertureManager _reevaluatePromotedElements]` while one of OITI's elements was live. After 5 catches in one SpringBoard session, element creation stays off until a respring.
- `ELEMENT STUB identifier was sent -<selector>`: Apple asked OITI's identifier object for something other than `elementIdentifier` / `clientIdentifier`. Once per selector per launch.

Level 1 adds:

- `NOTIF banner request <request> bundle=... app=... title=... message=... (feature on|off)`: one line per banner, with the title and message cut to 40 and 60 characters. **These lines contain notification text; look before sharing a log.**
- `NOTIF stock banner window restored after N s`, `NOTIF haptic played`.
- `HELLO startup prototype presented`, `suppressed by five-minute cooldown`, `activity observed before prototype presentation`, `promoted startup animation ahead of charging activity`, and `yielding startup card`: startup eligibility and handoff events. The prototype is controlled by `IslandStartupHelloEnabled` (default off); its persistent cooldown timestamp is `IslandStartupHelloLastPlayedAt`.
- `ELEMENT registered <identifier> (<reason>) registrar=... registration=... duration=...`, `STACK layout ...` (compact/expanded mode plus alert/activity behavior), `STACK separate-cards ... compactCards=N`, `STACK full ... evicting oldest ...`, and `STACK removed ... remaining=N`. In expanded/wide styles, older notices are individually rounded, spaced cards in the newest notice's secondary content; they still share the outer expanded Island card. Expiration restarts on compact demotion and promotion. In Compact style, all items use compact mode. The Experimental Notification Stack toggle in OITI > Notifications disables multi-item stacking and replaces the previous notice when a new one arrives. Turning stacking off while notices are visible retains the newest and clears older items. These lines show stack transitions and per-item expiration/dismissal.
- `ELEMENT VIEWS element / parts / leading / trailing / primary / secondary` 0.9 s after registering: where each view ended up (frame, frame in window, hidden, alpha, window, superview chain).
- `ELEMENT CORNERS leading chain` (corner radius, mask and size of every ancestor) and `CORNERS applied +N` when `IslandNotificationsCornerExtra` is set.
- `ELEMENT GESTURES attached to SAUIElementView and SBSystemApertureWindow`, `TOUCH began (element|window) hit=<class> at <point>` (where a touch landed), `TAP on the notification element ... seen by <view>`, `tap ran -_executeDefaultAction: on NCNotificationShortLookViewController` (the normal case), `tap: no matching stock banner (found N), using the fallback`, then `open url ...` or `open app <bundle> via ... -> 1`, and `SWIPE up ...`.
- The **diagnostic hooks** (only installed at level 1, so they cost nothing at level 0): `REAL element ...` and `REAL parts ...` for Apple's own elements (identifiers, layout modes, which views each has), `PROBE <role> = <class>` followed by that class's methods (`CLASSQ` lines), `TRACE ...` (what Apple asks OITI's element: `respondsToSelector:`, `conformsToProtocol:`, `isKindOfClass:`, accessors), `VCFOR element=... creating=N -> class|nil` (the manager's view controller lookup), `VCINIT provider=... -> ...`, and `AUTH in=[...] previous=[...] out=[...]` (the authority's ordering).

Developer tools (level 1):

| Item | What it does |
| --- | --- |
| `touch /tmp/OITIPoC.trigger` | Shows a test notification element (app icon, title, message) without a real notification. |
| `/tmp/OITIPoCSample.txt` | Optional text for that test element: title, message, bundle id, subtitle, one per line (empty lines are skipped). Remove it afterwards. |
| `IslandNotificationsHelloOnBoot` | If set to 1, shows the test element 10 s after every launch (default 0). |
| `IslandNotificationsDevLayout` | Forces a layout variant (1 compact, 3 min 1 / preferred 2 / max 3, 4 charging-like, 5 expanded, 6 wide), ignoring the Style picker. |
| `IslandNotificationsPoCRegistrar` | 0 registers through `SBSystemApertureController` (default), 1 through the SAUI manager (the old way; fails). |

Commands and the reporting recipe for testers: `COMMANDS.md`, section 13.
