# OITI 0.2.0 Beta 1: Island Notifications

This is a **beta** for testers. It is built from the `experiments` branch and marked as a pre-release.

## What's new

- **Island Notifications.** Each notification banner (Messages, Instagram, YouTube, Snapchat and so on) shows up as an element in the Dynamic Island instead of the banner at the top of the screen. The Island expands to fit the app icon, title and message, stays for a few seconds, then goes away. Tap it to open the notification (it goes where tapping the stock banner would go, such as the conversation), swipe up to dismiss it. A newer notification replaces the one on screen.
- **Styles.** Expanded (the polished one), Wide and Compact (both experimental).
- **Haptic.** An optional short, light haptic when a notification banner arrives. It works with or without Island Notifications.
- **Settings.** Settings > OITI > Notifications has the switches, the style picker, and sliders for duration (2 to 10 s), message lines (1 to 4) and Island roundness.
- A new, cleaner settings UI for the OITI pages.

Notifications without a title show the app name instead, and a subtitle (a group chat name, for example) is folded into the message.

## Before you install

- Rootless iOS 16 jailbreak (tested on Dopamine 3). **Only tested on an iPhone 8 Plus on iOS 16.7.16.** Other devices and iOS 16 builds may behave differently, which is exactly what this beta is for. It has not been tested on a real Dynamic Island iPhone.
- OITI needs OITCore. Install **both** `.deb` files (OITCore first, or both in one `dpkg -i`).
- The Island has to be on (OITI's Enable Dynamic Island, or real hardware). With it off, the stock banner stays.
- Island Notifications is **off by default.** Turn on **Show Notifications in the Island** and **Hide the Stock Banner** in Settings > OITI > Notifications.

## Please test

1. Send yourself a few notifications (a message, an app notification, one with a long text, one with no title).
2. Try the three styles. Wide and Compact are experimental: in Compact the app icon showed but the text did not in my testing. Tell me what you see.
3. Tap the notification (it should open what the notification would open, such as the conversation, not just the app) and swipe up on another.
4. Turn on **Notification Haptic**, then check it with Island Notifications off too.
5. Send two notifications close together.
6. Tell me about anything that looks wrong, is cut off, covers something, or makes SpringBoard respring.

## Known limits

- A new notification replaces the one on screen (there is no queue yet).
- Only notifications that become a banner are handled. Notifications delivered straight to the lock screen are not, and they get no haptic.
- Compact and Wide are experimental, as above.

## If something goes wrong

- Turn off **Show Notifications in the Island** and **Hide the Stock Banner**. The stock banners come back.
- If SpringBoard keeps restarting, OITI's safe mode turns its hooks off after 5 launches in 2 minutes. Wait, then respring once. Always leave about 2 minutes between resprings while testing.
- To report a problem, follow "Reporting a problem (testers)" in `COMMANDS.md`, section 13, and send the output. The log contains the first characters of your notification titles and messages, so read it before sharing.

## Notes

- OITI is a fork of VisibleIsland by ethxnn88 (used with permission). Island Notifications was written from scratch; no code was copied from other tweaks.
- OITS (the status bar tweak) is not part of this release.
