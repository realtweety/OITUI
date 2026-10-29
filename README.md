# Tellus

**Tellus** (OITUI, *Order In The User Interface*) is my current project: a small family of tweaks that make an iPhone running iOS 16 look and feel as modern as possible. It is built for rootless jailbreaks (Dopamine-style) and made and maintained by me, solo.

Every tweak has two names. The **Latin name** is what you see in Sileo and Settings. The **OIT name** is the technical name that stays in package IDs, files, logs and the docs.

| You see | Technical name | What it is |
| --- | --- | --- |
| **Insula** | OITI | Gives iPhones without a Dynamic Island a Dynamic Island, and the settings, notifications and download progress around it |
| **Litus** | OITS | Repositions the status bar elements around the Island (work in progress, paused for now) |
| OITCore | OITCore | The shared library. It installs as a dependency of Insula, so you install it first |
| OITInspector | OITInspector | A read-only developer tool for runtime dumps (not needed to use anything else) |

Tellus is being developed and tested on an **iPhone 8 Plus** jailbroken with **Dopamine 3** on **iOS 16.7.16**. Other devices and iOS builds may behave differently, so please tell me what you find.

<!-- screenshot: the Insula Settings page (main page) -->

---

# Insula (OITI)

Insula, or Order In The Island, gives devices without a Dynamic Island a Dynamic Island. It is built on Apple's own Island system and does not draw a fake one on top. Insula provides the Island itself and its positioning, appearance, size and scale, and then adds the things that make it useful: notifications in the Island, a startup animation prototype, and download progress.

I am hoping to keep adding quality-of-life features and customization, so recommendations on how to improve and expand Insula are very welcome.

## What it does

- **The Island:** turn the Dynamic Island on, move it, and resize or scale it (the width and height scales are relative to Apple's own size, so 1.0 is the stock Island). Colour, opacity and notification banner offsets are adjustable and apply live.
- **Apple Mode:** one switch that turns every Island customization off at once so you can see how the stock Island behaves. It keeps Enable Dynamic Island, the built-in position and notification fixes, the Status Bar Layout setting and safe mode.
- **Island Notifications:** see below.
- **Download Progress:** see below.
- **Startup Animation (prototype):** see below.
- **Safe mode:** if SpringBoard restarts several times in a short window, Insula switches its tweaks off by itself. Settings then shows a banner with the reason and a **Clear Safe Mode & Respring** button.

<!-- screenshot: the Island with a notification -->

## Island Notifications

Island Notifications shows each notification banner (Messages, Instagram, YouTube, Snapchat and the rest) as an element in the Island instead of the banner at the top of the screen. The Island expands to fit the app icon, title and message, stays for a few seconds, and goes away. Tap it to open the notification (it goes where tapping the stock banner would go), swipe up to dismiss it.

It is off by default. Turn it on in **Settings > Insula > Notifications**:

- **Show Notifications in the Island** and **Hide the Stock Banner** (turn both on)
- **Style:** Expanded (the polished one), Wide or Compact (both experimental)
- **Duration**, **Message Lines** and **Roundness** sliders
- **Notification Haptic:** a short, light tap when a banner arrives. It works with or without Island Notifications.

The stack keeps up to four notices. Expanded and Wide show the newest as the main item and older notices as individual rounded compact cards inside the expanded Island card; Compact keeps all notices compact. **Stack Multiple Notifications (Experimental)** is a separate toggle. The stack is usable but not polished yet.

If something looks wrong, turn the two switches off and the stock banners come back.

## Download Progress

Download Progress shows a download in the Island while it happens. It is off by default and lives in **Settings > Insula > Download Progress**. Turn on **Show Download Progress**, then **Show App Store Downloads**.

- **Two looks:** **Minimal** is Insula's own black pill that sits over the Island, and **Detailed** is a real Island element.
- **What you see:** the app name, a progress bar with the percentage, and an estimate of the time left. Pausing a download in the App Store shows **Paused**, and cancelling shows a short red **Cancelled**. When a download finishes, the Minimal pill's text fades, the bar becomes a green circle and a check mark is drawn in it.
- **Which downloads:** App Store installs and updates. TestFlight installs have not been tested yet.
- **Percentage only:** iOS only exposes a percentage for App Store downloads, so there are no sizes or speeds for those. (The built-in test download, started from the same page, does show sizes and speed.)
- **Going away:** the bar ends when the downloads finish, or after a time limit you set, or when you swipe it away. The download itself carries on.
- **Browsers:** downloads in Safari, Chrome and Arc are planned for later, as their own project.

<!-- screenshot: the Minimal pill during an App Store download -->
<!-- gif: the completion animation -->

## Startup Animation (prototype)

An off-by-default prototype that waits until the device is unlocked and on the Home Screen, then plays a six-second Hello animation as a muted video, at most once every five minutes. During playback Insula promotes it ahead of the system charging activity; calls and other Island activity interrupt it.

## Privacy and bug reports

Insula does not send notification text anywhere, and at the default diagnostic level nothing about your notifications is written to a log. If you need to send a bug report, you can raise the diagnostic level:

```
defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 1
```

then respring, reproduce the problem and read `/tmp/OITIDebug.log`. At higher levels the log holds the first characters of notification titles and messages, so **read it before you share it**. `DIAGNOSTICS.md` explains the log and the dumps. Set the level back to 0 afterwards.

## Settings attribution

Insula's Settings pages are adapted from [Liquid (Gl)Ass by Winaviation](https://github.com/winaviation-tweaks/liquidass), licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/). The pages were modified for Tellus; the upstream author does not endorse Tellus. The full license text is in `Third Party Licenses/LIQUIDASS-LICENSE.txt`.

Insula is a fork of [VisibleIsland](https://github.com/ethxnn88) by ethxnn88, used with written permission.

---

# Litus (OITS)

Litus, or Order In The Status Bar, has a pretty specific use case. I have an iPhone 8 Plus, a notchless device, and I use Insula to give it a Dynamic Island. On notchless devices the clock is centered instead of on the left of the screen. Litus can change the position of every major status bar element along the X axis, and you can also hide those same elements completely. Y axis customization is something I would like to add.

Litus is a work in progress and I have paused it for now to focus on Insula. It is in a fairly usable state (some status bar elements are much less stable than others). Recommendations are welcome.

---

# OITCore

OITCore is the common library my tweaks share: logging, preferences, device information and notifications. It does not do a lot yet, and it is installed automatically as a dependency of Insula. It will grow when the tweaks need more shared pieces.

---

# Status, as of October 28, 2026

- **Insula** is where all the work is going. The latest release is 0.2.0. Version 0.3.0 is in progress and a beta is coming, with Download Progress, Apple Mode, live colour, opacity and offset settings, relative scaling, safe-mode visibility and a fix for a crash when picking some options in Settings.
- **Litus** is paused.
- **OITCore** changes only when the tweaks need it.

---

# Installation

**Latest release:** [Tellus v0.2.0](https://github.com/realtweety/OITUI/releases/tag/v0.2.0). Install both `.deb` files, **OITCore** and **Insula** (OITI). OITCore first, or both in one `dpkg -i`. Insula will not install without OITCore.

Older releases:

- [v0.1.0](https://github.com/realtweety/OITUI/releases/tag/v0.1.0): the latest release of OITI and OITCore at that time
- [first_release](https://github.com/realtweety/OITUI/releases/tag/first_release): the latest release of OITS (Litus) and the first releases of OITI and OITCore

You need a rootless jailbreak on iOS 16. To remove everything, remove Insula before OITCore.

---

# Documentation

- `OVERVIEW.md`: the modules, names, current state and plans
- `COMMANDS.md`: commands and test steps
- `DIAGNOSTICS.md`: logging, dumps and how to read them
- `LEARNINGS.md`: technical constraints and lessons
- `WORKFLOW.md`: branches, pull requests and releases
- `IDEAS.md`: the backlog
- `OITUI_HISTORY.md`: how the project got here
- `Third Party Licenses/`: license texts for third-party work
