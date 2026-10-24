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
| Install dump trigger | `touch /tmp/OITIInstallDump.trigger`, or Darwin notification `com.wilburt.oiti/InstallDump` (needs level 1 or higher; see "OITI install progress dump" below) |
| Install dump keys | `InstallDumpSamples` (0 to 30, default 6), `InstallDumpIntervalSeconds` (1 to 10, default 2) |
| Prefs keys | `DiagnosticsEnabled` (bool, default on), `DiagnosticsLevel` (0–2, **default 0**) |

At level 0 OITI writes only `SESSION`, `GUARD`, `SAFE`, `CHECK` and a few `NOTIF` / `ELEMENT` lines (the two install lines and any failure, see below), about a dozen per boot, and that includes every warning (respring-loop guard, safe mode, MobileGestalt spoof self-check). It runs no polling timer and tracks no windows. Level 1 adds events and state changes (`PREF`, `ISLAND`, `CURTAIN`, `COLOR`, `BANNER`, `GAINMAP`, `TOUCHPASS`), starts the trigger-file poll and takes one baseline dump after the Island first lays out. The aperture research build also logs rate-limited `APERTURE` element-construction and manager-registration events at level 1. Level 2 adds rate-limited per-call lines (`LAYOUT`).

```
defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 1
sbreload
```

Safe mode: after 5 SpringBoard launches within 120 s OITI stops installing its hooks until `/var/mobile/Library/Preferences/OITISafeMode.plist` is removed (or Darwin notification `com.wilburt.oiti/ClearSafeMode`, or the **Clear Safe Mode & Respring** button in the banner that every OITI settings page shows while it is on), then respring. Installing or upgrading the package clears it.

A respring requested from OITI's own settings (the Respring button, or Clear Safe Mode) first writes `/var/mobile/Library/Preferences/OITIRespringIntent.plist` with a timestamp. On the next launch the guard deletes it; if it is under 30 s old the launch is not counted and the launch history is cleared (`GUARD respring requested from OITI settings N s ago: launch not counted, history cleared`). An older marker is ignored (`GUARD ignored a stale respring marker`). Resprings from elsewhere still count, so a real crash loop trips the guard as before. Untested on-device (build `OITI-exp-2026-10-20-a`).

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

The native provider `auto` returns comes from, in order: the record the phone wrote about itself (`/var/mobile/Library/Preferences/OITINativeProvider.plist`), a table entry read from a device's own log (Island off; `iPhone14,4`, the 13 mini, uses `_UIStatusBarVisualProvider_Split1080_Wide`), and a guess by native pixel width. The decision text in the `CHOICE` line says which one answered.

`LEARN` lines (level 0, untested, build `OITI-exp-2026-10-20-b`): the first time a launch with the Island off builds a status bar, OITI records the provider UIKit chose. It only records when the answer is certainly native: the Island was off when SpringBoard started and still is, the phone is a notch iPhone in the device table, UIKit chose a real provider (not nil, not Fallback), the MobileGestalt cache does not hold the spoofed 2556 and no `UIStatusBarVisualProviderClassName` override is set. One attempt per launch; an identical record is not rewritten; a record for another machine identifier is ignored. The level 1 boot report adds a `NATIVE` line with the provider `auto` would use and where it came from.

Steps and commands: `COMMANDS.md`, section 12.

### OITI download progress (DOWNLOAD, untested, build `OITI-exp-2026-10-21-d`)

Level 0 lines, all rare: `DOWNLOAD started <id> (<title>), total <size>`, `progress element up for <title>`, `limit reached (<size> downloaded | N s on screen): the Island returns to idle, the download carries on`, `finished <id>` / `cancelled <id>`, `progress element removed (<reason>): it stays away until the next download starts` (a swipe, a notification replacing it, or stack capacity), and `test download started: <size> (Download Progress is on | OFF, so nothing will show)`. Presenting goes through the normal element path, so `ELEMENT` lines (registered, `RECOVERY`, the breadcrumb) also appear. If the element cannot be presented (no manager seen yet, recovery window, creation failure) the tracker retries every 10 s instead of every tick. `the progress element left the screen after N s but nothing in OITI removed it, so the system ended it (drop N of 5)` means Apple ended the element on its own (its alert timer, or something taking over the Island); the tracker puts it back after 1.5, 4.5, 13.5 and 30 s on successive drops and logs `giving up on putting the progress element back for this download` after five. The alert timer is answered by `preferredAlertingDuration:`, which returns 24 hours for a download element and the notice duration for everything else, so this line should not appear in normal use. The Minimal pill logs `progress pill up for <title> (window level N)`, then two state lines, `pill shown:` and `pill 0.8 s later:`, with the window's hidden flag, scene, level, key state, whether the pill is in that window, alpha, on-screen frame and `island={...} (<source>) -> pill={...}` (the source says whether the Island's own pill view was found or the rectangle was computed from the stock size), and `progress pill dismissed (<reason>)` where the reason is swipe, download-limit, download-complete, download-cancelled, restyle or feature-disabled. Per-tick progress is not logged.

### OITI install progress dump (INSTALL, untested, build `OITI-exp-2026-10-24-a`)

Download Progress stage 2, step 1: a read-only look at what SpringBoard exposes about an install that is running (App Store download, later an update and a TestFlight install). It exists to answer one question before any source is written: is there an `NSProgress` with real byte counts, or only a fraction? Nothing is hooked, nothing is written, and nothing on screen changes. Apple Mode does not switch it off (like the other dumps it is a diagnostic, not a customization). It also works in safe mode.

Gating: it runs only on request and only at `DiagnosticsLevel` 1 or higher. At level 0 no timer exists for it, and a request through the Darwin notification just logs `install dump request ignored: DiagnosticsLevel is 0`. The trigger file is detected by modification time (never deleted, never re-run at boot), so a crash while dumping cannot loop.

What it calls. Only zero-argument getters of private objects whose names contain a progress-related word (progress, fraction, percent, install, download, byte, total, completed, expected, unit, state, paus, cancel, placeholder, updat, status, phase, throughput, remaining). A name that starts with an action verb (start, stop, cancel, pause, resume, remove, delete, reload, refresh, ...) is never called, and `install`, `download` and `update` are only called when a noun follows (`installState`, `downloadProgress`) or the word continues in lower case (`installed`, `downloading`). Every class and selector is found by name at run time; the class names in the code and in `OVERVIEW.md` are guesses and the output says which exist. Objects are only described when their name or declared class looks relevant; an `NSProgress` is always described in full.

Each run is a snapshot followed by compact samples (default 6, every 2 s) so you can see whether values move. Lines carry the tag `INSTALL` and a phase in brackets: `[snapshot]` or `[sample 3/6 +6s]`.

| Line | Meaning |
| --- | --- |
| `=== BEGIN #n ... ===` / `=== END #n ===` | One run, with build, OS, machine and sample settings. Several runs in one log are separated by your `MARK` lines. |
| `CLASSES` | Loaded classes whose names mention placeholder, install, download or a progress view (SB, IX, MI, FBS and AS names first; UIKit, Foundation and CoreAnimation names skipped), with superclass and image. At most 120. |
| `CLASSPROBE` | The guessed classes (`SBApplicationPlaceholder`, `SBApplicationPlaceholderController`, `SBApplicationController`, `SBApplication`, `SBIconController`, `SBHIconManager`, `SBIconModel`, `SBLeafIcon`, `SBApplicationIcon`, `SBIconView`, `SBIconProgressView`, `IXAppInstallCoordinator`, `IXPlaceholder`, `FBSApplicationPlaceholder`): `not loaded in this process`, or present with chain and image, plus their own methods that mention progress, install, download, placeholder, fraction, percent, byte, pause, update, status or phase, with type encodings (at most 30 per class and kind). |
| `CONTROLLERS`, `SOURCE`, `ITEMS` | Which shared controllers were found, which collection getters answered (applications, placeholders, bundle identifiers, leaf icons) and how many objects of which class they hold. |
| `CANDIDATE` | An app, placeholder or icon that is a placeholder class or has a progress-like getter returning something non-zero or non-nil (`active=[...]`). At most 12. Followed by `OBJECT`, `GET` (getter values) and `IVAR` lines for it. |
| `VIEWS`, `PROGRESSVIEW`, `ICONVIEW` | The Home Screen view walk (all windows): how many views were visited, progress-looking views with their ancestry and frame, and icon views whose icon or view reports progress or is a placeholder. If no icon views exist the `HINT` line says to open the Home Screen page that shows the installing icon. |
| `PROGRESS ... NSProgress@...` | An `NSProgress` found anywhere above: `fraction`, `completed`, `total`, `indeterminate`, `paused`, `cancelled`, `finished`, kind, `fileOperationKind`, `throughput`, `eta`, file counts, `fileURL`, descriptions and `userInfo`, then a units guess (`BYTES`, percentage, bare fraction, unclear). |
| `GET ... = ` / `IVAR ... = ` with a progress, fraction or percent name | A numeric progress value that is not an `NSProgress`. Every one is also collected for the verdict as a `FRACTION` finding. |
| `VERDICT` | End of the snapshot: every `NSProgress` found, up to ten fraction-like values, and how to read them. |
| `SUMMARY` | End of each sample: how many `NSProgress` objects and fraction values were found. |
| `ERROR`, `(output budget used up ...)` | An exception that was caught, or the describe budget (160 lines for the snapshot, 24 per sample) was reached. |

Reading it: an `NSProgress` whose total is large and whose `completed` grows between samples is real bytes (sizes and speed are possible). A total of 100, or only `FRACTION` lines, means a fraction only (percent and bar work, sizes would show `?`). Nothing at all means the install was not visible to the dump (icon not on the visible Home Screen page, nothing downloading, or the object is not where the dump looks); `CLASSPROBE` and `CLASSES` then say what to query next with `/tmp/OITIClassQuery.txt`.

Output is bounded (typically a few hundred lines for a snapshot and about 1,300 at the very most, under the logger's 4000-line backlog). The `CANDIDATE`, `ICONVIEW` and `ITEMS` lines can contain the name and bundle identifier of the app being installed and of other apps on the Home Screen page; read them before sharing a log. Steps and commands: `COMMANDS.md`, section 17.

### OITI Island Notifications and Startup Animation (NOTIF, ELEMENT and HELLO, 0.2.0)

Two tags cover the feature. `NOTIF` is the banner hook and the stock banner. `ELEMENT` is the Island element's life. At level 0 only the install lines and failures are written (so a bug report always has them); everything else needs level 1.

Level 0:

- `NOTIF banner hook installed on -[SBNotificationBannerDestination postNotificationRequest:] (encoding v24@0:8@16)`, or `NOTIF banner hook NOT installed ...` followed by `CANDIDATES` lines listing the related methods (the selector differs between iOS versions).
- `ELEMENT promotion guard installed ...`, or `... NOT installed` with the reason.
- Failures: `no SAUISystemApertureManager seen yet`, `missing class`, `creation failed`, `exception while creating/registering the element`, `could not dismiss the element`, `could not open <bundle>`, `GESTURES: no host view found`, `element creation is off until the next respring`.
- `ELEMENT GUARD caught <exception>: <reason>` with the first ten stack symbols, `GUARD element` and `GUARD parts` lines for every registered element, and `dismissed element ...`. This is the promotion guard doing its job: an exception inside `-[SAUISystemApertureManager _reevaluatePromotedElements]` while one of OITI's elements was live. After 5 catches in one SpringBoard session, element creation stays off until a respring.
- `ELEMENT RECOVERY ...` (level 0, untested, build `OITI-exp-2026-10-21-c`): cross-launch crash recovery. While any OITI Island element (a notice or the startup Hello) is live, `/var/mobile/Library/Preferences/OITILiveElement.plist` exists (time, pid, reason, build); it is written just before the element is registered and deleted when the last one leaves, or when the promotion guard catches an exception. At launch, `RECOVERY the previous SpringBoard ended while an OITI Island element was live (...)` means the file was left behind: a crash, or a respring from somewhere other than OITI's own settings. That launch keeps Island notifications and the startup animation off for 120 s; each suppressed notice logs `RECOVERY: notification is not shown as an Island element (N s left); the stock banner is used`, and `RECOVERY window is over` marks the end. `RECOVERY not needed: SpringBoard was restarted from OITI's settings ...` means the respring was requested from OITI's Respring button (the loop-guard intent marker), so nothing is suppressed. Nothing else in OITI is affected.
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
