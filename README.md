# OITUI

OITUI, or Order In The User Interface, is the name of my current project. OITUI is made up of multiple components like OITS, OITI, and possibly more to come. The idea of OITUI is essentially to make your iPhone (Currently iOS 16 only) look and feel as modern as possible


# OITS

OITS, or Order In The Status Bar, is a tweak with a pretty specific use case. I have an iPhone 8 Plus, a notchless device, and I use OITI to give it a Dynamic Island. On notchless devices, the clock is centered instead of on the left of the screen. OITS can currently change the position of every major status bar element along the X axis and you can also fully hide those same major status bar elements completely (Going to add Y axis customization soon!). OITS is very much WIP, but it is in a fairly usable state I'd say (certain Status Bar elements are much more unstable and unreliable than others). Please feel free to give me any recommendations on how to improve and expand OITS!


# OITI

OITI, or Order In The Island, is a tweak that gives devices without a Dynamic Island a Dynamic Island. OITI focuses on providing the Dynamic Island itself, along with basic positioning, appearance, notification banner offsets, and Island re-sizing and scaling, but I am hoping that I will soon get around to giving it a lot more QoL, customization, and features. Just like with OITS, feel free to give me any recommendations on how to improve and expand OITI!

### Island Notifications (0.2.0 Beta)

Island Notifications shows each notification banner (Messages, Instagram, YouTube, Snapchat and the rest) as an element in the Island instead of the banner at the top of the screen. The Island expands to fit the app icon, title and message, stays for a few seconds, and goes away. Tap it to open the notification (it goes where tapping the stock banner would go), swipe up to dismiss it. It is built on Apple's own Island element system, so it does not draw a fake Island on top of the real one.

It is off by default. Turn it on in Settings > OITI > Notifications:

- **Show Notifications in the Island** and **Hide the Stock Banner** (turn both on)
- **Style:** Expanded (the polished one), Wide or Compact (both experimental)
- **Duration**, **Message Lines** and **Roundness** sliders
- **Notification Haptic:** a short, light tap when a banner arrives. It works with or without Island Notifications.

OITI does not send notification text anywhere, and at the default diagnostic level nothing about your notifications is written to a log (if you raise `DiagnosticsLevel` for a bug report, the log holds the first characters of titles and messages, so read it before sharing). If something looks wrong, turn the two switches off and the stock banners come back. See `RELEASE_NOTES_0.2.0-beta.1.md` for what to test and how to report a problem.

OITCore is a dependency of OITI, so you will need to install OITCore in order to install OITI

### OITI Settings attribution

The new OITI Settings pages take inpiration from Liquid (Gl)Ass made by Winaviation


# OITCore

OITCore is intended to give my tweaks a common "library" of utilities, functionalities, states, and possibly more. It really doesn't do a whole lot right now, but once my tweaks start getting more advanced I plan on using OITCore to store all sorts of different types of information between all the tweaks. Just like with the other two tweaks, give me any recommendations on how to improve and expand OITCore!


# Project Status As of October 18, 2026

OITS is very much still WIP, as stated above. I have sort of abandoned it (FOR NOW, I am focusing on OITI currently).

OITI is doing really great in my opinion. The most recent added feature is Island Notifications (0.2.0 Beta 1, with a style picker and an optional haptic), which I am very proud of. Before that came Island re-sizing and scaling.

OITCore isn't used a whole lot inside of OITUI as of right now, simply because the tweaks are pretty early in being developed and don't really have too much of a need for OITCore. BUT, like with the other things, I plan on giving OITCore a lot more features and uses

# Installation
**Beta:** this link brings you to OITI 0.2.0 Beta 1 (Island Notifications), a pre-release. Install both `.deb` files, OITCore and OITI (OITCore first, or both in one `dpkg -i`): https://github.com/realtweety/OITUI/releases/tag/v0.2.0-beta.1

This link will bring you to latest release of OITI and OITCore https://github.com/realtweety/OITUI/releases/tag/v0.1.0

This link will bring you to the latest release of OITS and the first releases of OITI and OITCore https://github.com/realtweety/OITUI/releases/tag/first_release

As stated above, OITCore is required to be installed with OITI. OITI will not install without OITCore.

OITUI is being tested on an iPhone 8 Plus jailbroken with Dopamine 3 running iOS 16.7.16
