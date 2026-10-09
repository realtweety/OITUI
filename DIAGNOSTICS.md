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

At level 0 OITI writes only `SESSION`, `GUARD`, `SAFE` and `CHECK` lines, about a dozen per boot, and that includes every warning (respring-loop guard, safe mode, MobileGestalt spoof self-check). It runs no polling timer and tracks no windows. Level 1 adds events and state changes (`PREF`, `ISLAND`, `CURTAIN`, `COLOR`, `BANNER`, `GAINMAP`, `TOUCHPASS`), starts the trigger-file poll and takes one baseline dump after the Island first lays out. Level 2 adds rate-limited per-call lines (`LAYOUT`).

```
defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 1
sbreload
```

Safe mode: after 5 SpringBoard launches within 120 s OITI stops installing its hooks until `/var/mobile/Library/Preferences/OITISafeMode.plist` is removed (or Darwin notification `com.wilburt.oiti/ClearSafeMode`), then respring. Installing or upgrading the package clears it.
