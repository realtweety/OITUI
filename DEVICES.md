# Insula device support and measurement

What the device table (`OITI/OITIDeviceProfiles.h`) does, which devices have an entry, what is verified and what is not,
and how a row is added. Written for the v0.3.0 polish (batch 1, build `OITI-exp-2026-11-01-b`). Nothing in this file claims a
measurement that has not been made.

## 1. What the table gates (read from the code)

`OITICurrentProfile()` looks the device's machine identifier up in the table. No entry means no profile, and exactly three
features then do nothing:

| Feature | Where | Without an entry |
|---|---|---|
| Fix Island Position (`fixEnabled`) | `OITIApplyIslandPosition` in `IslandSize/OITIIslandHooks.xm` | falls back to the custom position if that is on, otherwise nothing |
| Fix Notification Positioning (`notificationFix`) | `OITIBannerFrame` in the same file | nothing (custom banner position, if on, still works) |
| Status Bar Layout **Automatic** | `StatusBar/OITIStatusBarProvider.xm` | stays idle (the manual layouts still work) |

Everything else is device independent in the code: Enable Dynamic Island, custom Island and banner positions, Island size and
scale, colour, opacity, outline, notifications, Download Progress, Hello. "Independent in the code" is not "tested": the only
device any of it has been run on is the owner's iPhone 8 Plus (iOS 16.7.16, Dopamine).

Settings tells the user about a missing entry when Fix Island Position or Fix Notification Positioning is switched on
("No built-in offsets", or "Estimated offsets" when the entry is marked `verified = NO`), and both footers say so.

## 2. What "verified" means in the table today

`verified = YES` is inherited. The table was generated from six if/else chains in the old `Tweak.xm`, and `verified = NO` marks
the offsets that the original comments flagged as guesses. So `YES` means "not flagged as a guess upstream" (seven of 17 rows).
The project docs record no measurement (no log, no screenshot) for any of the 17 rows, so none of them is "measured by us".
This file does not change any existing row.

## 3. Identifier check (web, 2026-11-01)

Checked against EveryMac's identifier lists, DeviceAtlas, and the WebRTC iOS source (which cites Apple support pages).

| Device | Machine identifier(s) | In the table | Fix Island Position / Fix Notification Positioning / Status Bar Auto | Status |
|---|---|---|---|---|
| iPhone 14 Plus | `iPhone14,8` | no | inactive | identifier confirmed; no offsets known; no entry added |
| iPhone SE (2nd generation) | `iPhone12,8` | no | inactive | identifier confirmed; no offsets known; no entry added |
| iPhone SE (3rd generation) | `iPhone14,6` | no | inactive | identifier confirmed; no offsets known; no entry added |
| iPhone 8 | `iPhone10,1`, `iPhone10,4` | no | inactive | identifiers confirmed; needs measurement |
| iPhone 8 Plus | `iPhone10,2`, `iPhone10,5` | no | inactive | identifiers confirmed; needs measurement (the owner's phone) |

"Inactive" is the code's behaviour for any identifier without a row. It does not mean the device was tried and failed. The iPhone
SE models and the iPhone 8 / 8 Plus have a home button, so there is no sensor cut-out for the Island to align with; where the
Island should sit is a design choice, not a measured fact, and must be recorded as the owner's choice (see section 4).
No dimensions, offsets or screen sizes for these devices are stated here because none has been measured. The 14 Plus is a notched
device that ships with iOS 16, so it is a plausible later row, but any offsets for it must come from a measurement on that
identifier, not from the 13 Pro Max or 14 rows.

## 4. Measurement protocol (iPhone 8 / 8 Plus, reusable for any identifier)

Goal: record, from the real device, the values a table row needs: Island window `origin.y` (`islandY`), banner window
`origin.y` (`bannerY`) and banner window size (`bannerWidth` x `bannerHeight`). One build, one phone, one iOS version per run.

1. **Prepare.** On the phone: `defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 1`. In Settings > Insula: Enable
   Dynamic Island on, **Apple Mode** on (it forces every customization off, so Apple's own frames are logged), Fix Island
   Position and Fix Notification Positioning off. Respring, then wait 2 minutes (the loop guard counts quick launches).
2. **Capture stock frames.** Start a timer so the Island is on screen. `touch /tmp/OITIDump.trigger`. Receive one real
   notification (banner). Copy the log: `scp -P 2222 root@127.0.0.1:/tmp/OITIDebug.log ~/Downloads/OITIDebug.log`.
3. **Summarise.** `python3 tools/measure_device.py ~/Downloads/OITIDebug.log` prints the machine identifier, iOS version, screen
   and native bounds, whether the table has an entry, the Island window frames seen with every customization off, and the
   banner frames Apple asked for. It prints only what the log says and never suggests an offset.
4. **Choose the Island position.** Apple Mode off, Use Custom Position on. Adjust Y until the Island sits where you want it
   on this device; write the number down and take a screenshot. That chosen number is `islandY`. (On a notched phone the target
   is the sensor cut-out; on a home-button phone it is your choice, so say so in the record.) Note that custom position values are
   divided by the Y scale, which is 1.0 for this protocol.
5. **Choose the banner position.** Use Custom Notification Position on, Fix Notification Positioning off; adjust Y until a real
   banner sits where you want it below the Island; record the number and a screenshot. That is `bannerY`. The banner size is the
   `in=` frame from step 3; it should equal the screen size in points (the existing rows do).
6. **Record.** Add one line to the table in section 5 with the identifier, date, build tag, iOS version, the three numbers,
   the evidence kept (log file name, screenshots) and the status. Keep the log and screenshots outside the repo or in a
   dedicated folder; do not paste them into the docs.

**Status words.** *Measured*: all three values come from steps 3 to 5 on that exact identifier, and the evidence is kept.
*Estimated*: derived by analogy or by eye; the row must be `verified = NO`. *Unmeasured*: no row.

**Adding a row** (only after a *measured* or explicitly *estimated* record exists): append one row to `kOITIDeviceProfiles`,
`verified = YES` only for *measured*. A sibling identifier (for example `iPhone10,2` when only `iPhone10,5` was measured) gets no
row until it is measured itself, because it is a different machine identifier; if you decide to copy values across, mark that row
`verified = NO` and say why in this file. Update the "Device table" lines in `OVERVIEW.md` and `IDEAS.md` in the same change.

## 5. Measurement records

| Identifier | Date | Build | iOS | islandY | bannerY | Banner size | Evidence | Status |
|---|---|---|---|---|---|---|---|---|
| (none recorded yet) | | | | | | | | |
