# OITUI Commands

Every command used while working on OITUI, grouped by purpose. Each command is complete and exact: copy it as written.

## How to read this

- **Where** says which terminal to use.
  - **Phone**: type it after logging in with `ssh -p 2222 root@127.0.0.1`.
  - **Arch PC** / **Mac**: type it in a normal terminal on that computer.
- **†** means the command is written from the project's setup but has not been confirmed working on your setup yet.
- Phone commands: never add a trailing `# comment`. The phone shell passes it to the command as arguments.
- Tables only hold commands without a pipe (`|`) so they copy cleanly. Commands that need one are in the code blocks under each table.

## 1. Machines

| Machine | Repo folder | Theos device settings | Shell |
| --- | --- | --- | --- |
| Arch PC | `~/OITUI` | `THEOS_DEVICE_IP=localhost THEOS_DEVICE_PORT=2222` | fish |
| Mac | `~/theos-projects/OITUI` | `THEOS_DEVICE_IP=127.0.0.1 THEOS_DEVICE_PORT=2222` | zsh |

## 2. Connect to the phone

| Command | What it does | Where |
| --- | --- | --- |
| `iproxy 2222 22` | Starts the USB tunnel. Leave it running in its own terminal. | Arch PC, Mac |
| `ssh -p 2222 root@127.0.0.1` | Logs in to the phone. | Arch PC, Mac |
| `exit` | Leaves the phone session. | Phone |
| `scp -P 2222 root@127.0.0.1:/tmp/OITIDebug.log ~/Downloads/OITIDebug.log` | Copies the OITI log to the PC. | Arch PC |
| `scp -P 2222 root@127.0.0.1:/tmp/OITIDebug.log ~/Desktop/OITIDebug.log` | Copies the OITI log to the Mac desktop. | Mac |
| `scp -P 2222 root@127.0.0.1:/tmp/OITSDebug.log ~/Downloads/OITSDebug.log` | Copies the OITS log to the PC. | Arch PC |
| `scp -P 2222 root@127.0.0.1:/tmp/OITIPrefsDebug.log ~/Downloads/OITIPrefsDebug.log` | Copies the OITI settings log to the PC. | Arch PC |

The phone asks for the root password at every login and at every install step. `make package install` asks for it twice.

## 3. Build and install

Build **OITCore first** whenever OITCore changed, because OITI and OITS compile against its installed headers. Run the block for your machine from any folder.

Arch PC:

```
cd ~/OITUI/OITCore
THEOS_DEVICE_IP=localhost THEOS_DEVICE_PORT=2222 make package install
```

```
cd ~/OITUI/OITI
THEOS_DEVICE_IP=localhost THEOS_DEVICE_PORT=2222 make package install
```

```
cd ~/OITUI/OITS
THEOS_DEVICE_IP=localhost THEOS_DEVICE_PORT=2222 make package install
```

Mac:

```
cd ~/theos-projects/OITUI/OITCore
THEOS_DEVICE_IP=127.0.0.1 THEOS_DEVICE_PORT=2222 make package install
```

```
cd ~/theos-projects/OITUI/OITI
THEOS_DEVICE_IP=127.0.0.1 THEOS_DEVICE_PORT=2222 make package install
```

```
cd ~/theos-projects/OITUI/OITS
THEOS_DEVICE_IP=127.0.0.1 THEOS_DEVICE_PORT=2222 make package install
```

OITInspector (†), Arch PC:

```
cd ~/OITUI/OITInspector
THEOS_DEVICE_IP=localhost THEOS_DEVICE_PORT=2222 make package install
```

| Command | What it does | Where |
| --- | --- | --- |
| `make package` | Builds the `.deb` without installing. Phone not needed. Run inside a module folder. | Arch PC, Mac |
| `make clean package` | Full rebuild without installing. Run inside a module folder. | Arch PC, Mac |
| `grep -c OITLogger ~/theos/include/OITCore/OITLog.h` | Checks that the installed OITCore header is the new one. Prints a number above 0. | Arch PC, Mac |

Build notes:
- The arm64e linker warnings ("incompatible arm64e ABI compiler") on the Arch PC are harmless for your iPhone 8 Plus. Do not publish `.deb` files built on the Arch PC.
- dpkg's "downgrading" warning is harmless. Each machine counts the package build number separately.

## 4. Respring and settings on the phone

| Command | What it does | Where |
| --- | --- | --- |
| `sbreload` | Restarts SpringBoard (respring). Your SSH session may drop. | Phone |
| `defaults read com.wilburt.oiti.prefs` | Shows every OITI setting. | Phone |
| `defaults read com.wilburt.oits.prefs` | Shows every OITS setting. | Phone |

The phone's `defaults` has no `delete` mode. Set a value instead, as below.

Diagnostics level (0 = quiet default, 1 = events and dumps, 2 = also per-call lines). Run `sbreload` after changing it.

| Command | What it does | Where |
| --- | --- | --- |
| `defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 0` | OITI quiet: only `SESSION`, `GUARD`, `SAFE`, `CHECK` lines. | Phone |
| `defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 1` | OITI events, state changes and dumps. | Phone |
| `defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 2` | OITI everything, including per-layout lines. | Phone |
| `defaults write com.wilburt.oits.prefs DiagnosticsLevel -int 0` | OITS quiet. | Phone |
| `defaults write com.wilburt.oits.prefs DiagnosticsLevel -int 1` | OITS events, state changes and heartbeat. | Phone |
| `defaults write com.wilburt.oits.prefs DiagnosticsLevel -int 2` | OITS everything. | Phone |
| `defaults write com.wilburt.oiti.prefs DiagnosticsEnabled -bool false` | Turns all OITI diagnostics off. | Phone |
| `defaults write com.wilburt.oiti.prefs DiagnosticsEnabled -bool true` | Turns OITI diagnostics back on. | Phone |
| `defaults write com.wilburt.oits.prefs DiagnosticsEnabled -bool false` | Turns all OITS diagnostics off. | Phone |
| `defaults write com.wilburt.oits.prefs DiagnosticsEnabled -bool true` | Turns OITS diagnostics back on. | Phone |

Respring-loop guard settings (OITI):

| Command | What it does | Where |
| --- | --- | --- |
| `defaults write com.wilburt.oiti.prefs SafeModeGuardEnabled -bool false` | Turns the loop guard off. | Phone |
| `defaults write com.wilburt.oiti.prefs SafeModeGuardEnabled -bool true` | Turns the loop guard on (default). | Phone |
| `defaults write com.wilburt.oiti.prefs SafeModeRestoreGestalt -bool true` | On a guard trip, also run the MobileGestalt restore helper. † | Phone |
| `defaults write com.wilburt.oiti.prefs SafeModeRestoreGestalt -bool false` | On a guard trip, leave the Island spoof alone (default). | Phone |
| `defaults write com.wilburt.oiti.prefs SafeModeMaxLaunches -int 5` | Trip after 5 launches (default). | Phone |
| `defaults write com.wilburt.oiti.prefs SafeModeWindowSeconds -int 120` | Count launches within 120 seconds (default). | Phone |
| `defaults write com.wilburt.oiti.prefs SafeModeStableSeconds -int 45` | Forget the history after 45 stable seconds (default). | Phone |

## 5. Reading logs on the phone

OITI log (`/tmp/OITIDebug.log`):

| Command | What it does | Where |
| --- | --- | --- |
| `grep -e SESSION -e GUARD -e SAFE -e CHECK /tmp/OITIDebug.log` | The boot summary: build tag, loop guard, MobileGestalt self-check. | Phone |
| `grep -e CHECK /tmp/OITIDebug.log` | Only the self-check lines. | Phone |
| `grep -e PREF -e ISLAND -e CURTAIN -e COLOR -e BANNER -e GAINMAP -e TOUCHPASS /tmp/OITIDebug.log` | Setting changes and Island events (needs level 1 or higher). | Phone |
| `grep DUMP /tmp/OITIDebug.log` | Every dump line. | Phone |
| `grep CLASSQ /tmp/OITIDebug.log` | Class query results. | Phone |
| `grep METRICS /tmp/OITIDebug.log` | The layout-metrics values Apple builds the Island from, and the size multiplier in use. | Phone |
| `grep MARK /tmp/OITIDebug.log` | The labels you added with `dumpstate`. | Phone |
| `grep -c SESSION /tmp/OITIDebug.log` | Counts SpringBoard starts in the log. | Phone |
| `tail -n 40 /tmp/OITIDebug.log` | The last 40 lines. | Phone |
| `rm -f /tmp/OITIDebug.log /tmp/OITIDebug.log.1` | Deletes the OITI logs. A fresh one starts at the next respring. | Phone |

OITI settings log (`/tmp/OITIPrefsDebug.log`):

| Command | What it does | Where |
| --- | --- | --- |
| `grep GESTALT /tmp/OITIPrefsDebug.log` | Every MobileGestalt read, write and repair. | Phone |
| `cat /tmp/OITIPrefsDebug.log` | The whole settings log. | Phone |
| `rm -f /tmp/OITIPrefsDebug.log` | Deletes it. | Phone |

OITS log (`/tmp/OITSDebug.log`):

| Command | What it does | Where |
| --- | --- | --- |
| `grep -e SESSION -e PREF /tmp/OITSDebug.log` | Build tag and preference lines. | Phone |
| `grep -c SESSION /tmp/OITSDebug.log` | Counts SpringBoard starts in the log. | Phone |
| `grep -e REFUSED -e APPLY /tmp/OITSDebug.log` | Position changes OITS made or refused. | Phone |
| `grep -e TICKGAP -e TICKSLOW -e MAINSTALL /tmp/OITSDebug.log` | Main-thread stalls and slow ticks. | Phone |
| `grep -e MARK -e VIS -e SYS-SET -e REMOVE -e DEAD /tmp/OITSDebug.log` | Visibility changes and who caused them. | Phone |
| `grep DUMP /tmp/OITSDebug.log` | Every OITS dump line. | Phone |
| `tail -n 40 /tmp/OITSDebug.log` | The last 40 lines. | Phone |
| `touch /tmp/OITSDump.trigger` | Asks OITS for a status-bar dump (needs level 1 or higher). | Phone |
| `rm -f /tmp/OITSDebug.log /tmp/OITSDebug.log.1` | Deletes the OITS logs. | Phone |

Level-0 quiet test for OITI (confirms that the dump trigger does nothing at level 0):

```
grep -e SESSION -e CHECK /tmp/OITIDebug.log | tail -n 4
M=$(wc -l < /tmp/OITIDebug.log)
touch /tmp/OITIDump.trigger
sleep 4
tail -n +$((M+1)) /tmp/OITIDebug.log | grep -c DUMP
```

The last number should be `0` at level 0 and above `0` at level 1.

Crash logs:

| Command | What it does | Where |
| --- | --- | --- |
| `ls -t /var/mobile/Library/Logs/CrashReporter/SpringBoard-*.ips` | Lists SpringBoard crash logs, newest first. | Phone |
| `grep -il oit /var/mobile/Library/Logs/CrashReporter/SpringBoard-*.ips` | Lists crash logs that mention an OIT module. | Phone |

## 6. Island dumps (research)

Dumps need `DiagnosticsLevel` 1 or higher on OITI. Set it first and respring:

| Command | What it does | Where |
| --- | --- | --- |
| `defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 1` | Turns dumps on. | Phone |
| `sbreload` | Applies it. Wait about 10 seconds afterwards. | Phone |

Define the helper once per SSH login (it is forgotten when you log out):

```
dumpstate() { echo "$(date '+%m-%d %H:%M:%S') [MARK] $1" >> /tmp/OITIDebug.log; touch /tmp/OITIDump.trigger; }
```

One dump per phone state. Wait at least 3 seconds between them. The `sleep 10;` versions give you time to set up the phone after pressing Enter.

| Command | Phone state | Where |
| --- | --- | --- |
| `dumpstate idle-home` | Unlocked, on the home screen, nothing running. | Phone |
| `dumpstate idle-app` | An app (for example Settings) open and idle. | Phone |
| `sleep 10; dumpstate lockscreen` | Press Enter, then lock and wake the phone without unlocking. | Phone |
| `dumpstate spotify-collapsed` | Spotify playing, Island showing the compact player. | Phone |
| `sleep 10; dumpstate spotify-expanded` | Press Enter, then long-press the Island so the full player opens. | Phone |
| `dumpstate timer-compact` | A Clock timer running, on the home screen. | Phone |
| `dumpstate idle-home-scale1` | Same as `idle-home`, with "Use Custom Scale" turned off. | Phone |
| `dumpstate charging` | Just after plugging in the charging cable. | Phone |

Class queries. Do them one batch at a time, never all at once, so the logger does not drop lines.

Batch A (layout classes):

```
cat > /tmp/OITIClassQuery.txt <<'EOF'
SBSystemApertureSettings
SBSwitcherSystemApertureSettings
SBUISystemApertureLayoutMetrics
_SBSystemApertureLayoutState
_SBSystemApertureElementLayoutState
EOF
dumpstate classq-A
```

Batch B (controller and container classes). Wait a few seconds after batch A first:

```
cat > /tmp/OITIClassQuery.txt <<'EOF'
SBSystemApertureController
SBSystemApertureViewController
SBSystemApertureContainerView
_SBSystemApertureContainerViewContentView
SBSystemApertureStatusBarPillElement
EOF
dumpstate classq-B
```

Batch C (content classes). Wait a few seconds after batch B first:

```
cat > /tmp/OITIClassQuery.txt <<'EOF'
SBSystemApertureElementAuthority
SBSystemAperturePresentableManager
SBSystemApertureProvidedContentElement
SBChargingSystemApertureElementProvider
SBUISystemApertureElementSource
EOF
dumpstate classq-C
```

Batch D (more content classes). Wait a few seconds after batch C first:

```
cat > /tmp/OITIClassQuery.txt <<'EOF'
SBUISystemApertureElementConfiguration
SBUISystemApertureCustomContentProvider
SAUISystemApertureManager
SAUIElementViewController
SAUIElementView
EOF
dumpstate classq-D
```

| Command | What it does | Where |
| --- | --- | --- |
| `rm -f /tmp/OITIClassQuery.txt` | Removes the class query so later state dumps stay small. | Phone |
| `rm -f /tmp/OITIDump.trigger` | Removes the trigger file. | Phone |

When you are done, copy the log to the PC with the `scp` command from section 2 and upload it as a file.

## 6A. Island size (metrics)

Makes the Island itself smaller or larger while its contents keep their normal size. Only the width and height multipliers of Apple's `sensorRegionSize` are used (the experiments showed it is the root input; the other sizes follow from it). 1.0 is Apple's own size. Changes apply immediately, with no respring. You can also set these on the OITI > Scale page (Island Size sliders). Keep "Use Custom Scale" turned off while judging the result.

| Command | What it does | Where |
| --- | --- | --- |
| `defaults read com.wilburt.oiti.prefs` | Shows the current multipliers (`MetricsSensorWidthScale`, `MetricsSensorHeightScale`). A missing key means 1.0. | Phone |
| `grep METRICS /tmp/OITIDebug.log` | Shows Apple's real values, the multiplier in use, and every derived size. Needs `DiagnosticsLevel` 1 and a dump (`dumpstate metrics-check`). | Phone |

Small Island (70% width and 80% height):

```
defaults write com.wilburt.oiti.prefs MetricsSensorWidthScale -float 0.7
defaults write com.wilburt.oiti.prefs MetricsSensorHeightScale -float 0.8
```

Smaller Island (55% width and 75% height):

```
defaults write com.wilburt.oiti.prefs MetricsSensorWidthScale -float 0.55
defaults write com.wilburt.oiti.prefs MetricsSensorHeightScale -float 0.75
```

Narrower only (60% width, normal height):

```
defaults write com.wilburt.oiti.prefs MetricsSensorWidthScale -float 0.6
defaults write com.wilburt.oiti.prefs MetricsSensorHeightScale -float 1.0
```

Back to Apple's own size:

```
defaults write com.wilburt.oiti.prefs MetricsSensorWidthScale -float 1.0
defaults write com.wilburt.oiti.prefs MetricsSensorHeightScale -float 1.0
```

Allowed range is 0.3 to 2.0. The settings page sliders use 0.4 to 1.5 for width and 0.7 to 1.5 for height. Your 0.7 height looks fine on the phone. Below roughly 0.6 the 22 point Spotify artwork would no longer fit inside the pill (not tested).

Your minimal look (65% width and 70% height):

```
defaults write com.wilburt.oiti.prefs MetricsSensorWidthScale -float 0.65
defaults write com.wilburt.oiti.prefs MetricsSensorHeightScale -float 0.7
```

If the Island looks broken, run the "Back to Apple's own size" block. If SpringBoard keeps restarting, the loop guard switches OITI's hooks off after the fifth launch within 120 seconds. Then run the same block and clear safe mode (section 7).

## 7. Respring-loop guard and safe mode (OITI)

| Command | What it does | Where |
| --- | --- | --- |
| `cat /var/mobile/Library/Preferences/OITISafeMode.plist` | Shows whether safe mode is active and why. An error means it is not active. | Phone |
| `cat /var/mobile/Library/Preferences/OITIBootLog.plist` | Shows the recent SpringBoard launch times the guard counts. | Phone |
| `rm /var/mobile/Library/Preferences/OITISafeMode.plist` | Clears safe mode. Respring afterwards. | Phone |
| `rm -f /var/mobile/Library/Preferences/OITISafeMode.plist /var/mobile/Library/Preferences/OITIBootLog.plist` | Clears safe mode and the launch history. Respring afterwards. | Phone |
| `grep -e GUARD -e SAFE /tmp/OITIDebug.log` | The guard's decisions. | Phone |
| `cat /var/mobile/Library/Preferences/OITIRespringIntent.plist` | The marker OITI's settings leave just before they respring (Respring button, Clear Safe Mode). The guard deletes it on the next launch, so an error here is normal. † | Phone |

Safe mode also shows as a banner at the top of every OITI settings page, with a **Clear Safe Mode & Respring** button (`experiments` build `OITI-exp-2026-10-20-a`). A respring started from OITI's own Respring button or that button is not counted as a possible crash: the guard logs `respring requested from OITI settings N s ago: launch not counted, history cleared`. A respring from anywhere else (`sbreload`, another tweak, Dopamine) still counts.

Test the marker. After each respring wait for the Island, then reopen Settings > Insula and tap Respring again. Do this six times about 20 seconds apart, then:

```
grep -e GUARD -e SAFE /tmp/OITIDebug.log | tail -n 20
```

Every launch after the first should say `launch not counted`, and there should be no `TRIPPED`. Then check that a real loop is still caught: run `sbreload` over SSH five times, about 10 seconds apart. The fifth launch should log `TRIPPED`, OITI's changes disappear, and the banner appears on the settings pages. Tap **Clear Safe Mode & Respring** and confirm OITI's changes return.

Deliberately trip the guard. This fakes four recent launches, so the next respring is the fifth:

```
NOW=$(date +%s)
cat > /var/mobile/Library/Preferences/OITIBootLog.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>launches</key><array>
<real>$((NOW-30))</real><real>$((NOW-20))</real><real>$((NOW-15))</real><real>$((NOW-10))</real>
</array></dict></plist>
EOF
chown mobile:mobile /var/mobile/Library/Preferences/OITIBootLog.plist
sbreload
```

After about 10 seconds, `grep -e GUARD -e SAFE /tmp/OITIDebug.log` should show `TRIPPED`, and the Island should lose OITI's changes. Then clear safe mode with the `rm -f` row above and respring.

## 8. Island spoof (MobileGestalt)

Turn the Island on or off with the Island on/off switch on the main OITI settings page, never by editing files.

| Command | What it does | Where |
| --- | --- | --- |
| `cat /var/mobile/Library/Preferences/OITIGestaltBackup.plist` | Shows the restore backup. Healthy for this phone: `OriginalValuePresent` false and `CaptureSuspect` true. | Phone |
| `grep GESTALT /tmp/OITIPrefsDebug.log` | Every capture, write and repair of the cache. | Phone |
| `grep -a -A2 ArtworkDeviceSubType /var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist` | Shows the Island value in the cache (2556 means on). † | Phone |
| `cp /var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist /var/mobile/OITI-MobileGestalt-island-on.plist` | Takes a snapshot of the cache. Do this before any risky test. | Phone |
| `cp /var/mobile/OITI-MobileGestalt-island-on.plist /var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist` | Puts the snapshot back (the Island-on state). Then run `sbreload`. | Phone |
| `/var/jb/usr/libexec/OITIRestoreGestalt` | Runs the restore helper by hand, the same one the uninstall script runs. Then run `sbreload`. † | Phone |

## 9. Packages on the phone

| Command | What it does | Where |
| --- | --- | --- |
| `dpkg -l "com.wilburt.*"` | Lists the installed OIT packages and their versions. | Phone |
| `dpkg -r com.wilburt.oits` | Removes OITS. † | Phone |
| `dpkg -r com.wilburt.oiti` | Removes OITI. Runs the Island restore helper. Remove OITI before OITCore. † | Phone |
| `dpkg -r com.wilburt.oitinspector` | Removes OITInspector. † | Phone |
| `dpkg -r com.wilburt.oitcore` | Removes OITCore. Do this last. † | Phone |

Run `sbreload` after removing anything.

## 10. Git and GitHub

The repo folder is `~/OITUI` on the Arch PC and `~/theos-projects/OITUI` on the Mac. Run these inside it.

Go to the repo:

| Command | What it does | Where |
| --- | --- | --- |
| `cd ~/OITUI` | Goes to the repo. | Arch PC |
| `cd ~/theos-projects/OITUI` | Goes to the repo. | Mac |

Start a work session:

| Command | What it does | Where |
| --- | --- | --- |
| `git fetch --prune origin` | Updates what git knows about GitHub. | Arch PC, Mac |
| `git switch main` | Switches to main. | Arch PC, Mac |
| `git pull --ff-only` | Brings the current branch up to date and refuses to create merge commits. | Arch PC, Mac |
| `git switch experiments` | Switches to the working branch. | Arch PC, Mac |
| `git status --short --branch` | Shows the branch and uncommitted changes. | Arch PC, Mac |
| `git stash list` | Lists stashed work. | Arch PC, Mac |
| `git branch -vv` | Lists branches and what they track. | Arch PC, Mac |
| `git log --oneline -5` | The last five commits. | Arch PC, Mac |
| `git diff --stat` | Shows which files changed and by how much. | Arch PC, Mac |

Save your work on `experiments`:

| Command | What it does | Where |
| --- | --- | --- |
| `git add -A` | Stages every change. Read `git status --short` first. | Arch PC, Mac |
| `git commit` | Opens your editor to write the commit message. | Arch PC, Mac |
| `git push` | Uploads the branch. | Arch PC, Mac |

Unpack a downloaded file bundle (run from any folder):

```
tar -xzf "$(command ls -t ~/Downloads/oitui-*.tar.gz | head -n 1)" -C ~/OITUI
```

```
tar -xzf "$(command ls -t ~/Downloads/oitui-*.tar.gz | head -n 1)" -C ~/theos-projects/OITUI
```

The first is for the Arch PC, the second for the Mac. Each unpacks the newest `oitui-*.tar.gz` in Downloads into the repo.

Land tested work on `main` (squash merge):

| Command | What it does | Where |
| --- | --- | --- |
| `gh pr create --base main --head experiments --fill` | Opens a pull request using the commit messages. Only after the changes pass on the phone. | Arch PC, Mac |
| `gh pr view --web` | Opens the pull request in the browser. | Arch PC, Mac |
| `gh pr status` | Shows the state of your pull requests. | Arch PC, Mac |
| `gh pr merge --squash` | Squash-merges the pull request for the current branch. | Arch PC, Mac |

After the merge, make a fresh working branch from the updated `main`:

```
git fetch --prune origin
git switch main
git pull --ff-only
git branch -D experiments
git switch -c experiments
git push -u origin experiments
git rev-parse main experiments origin/experiments
```

The three hashes in the last line must match. If GitHub already deleted the remote branch, `git push -u` simply recreates it. `-D` is needed because a squash merge does not make the old branch look merged to git. Check the pull request shows as merged before running it.

GitHub login (once per computer):

| Command | What it does | Where |
| --- | --- | --- |
| `sudo pacman -S github-cli` | Installs the GitHub CLI. | Arch PC |
| `gh auth login` | Logs in to GitHub. | Arch PC, Mac |
| `gh auth setup-git` | Lets git use that login. | Arch PC, Mac |
| `gh auth status` | Shows who you are logged in as. | Arch PC, Mac |

One-time repository settings (†). Allows only squash merges and deletes merged branches:

```
gh api -X PATCH repos/realtweety/OITUI -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false -F delete_branch_on_merge=true -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY
```

Releases are created only from tested work on `main`. Build on the **Mac**, ship OITCore and OITI together, and do not ship OITS until it is verified. The current release is `v0.2.0` (OITI package version `0.2.0`; OITCore remains `0.1.0`).

After the PR is merged, run on the Mac from a clean checkout of `main`:

```
cd ~/theos-projects/OITUI
git fetch --prune origin
git switch main
git pull --ff-only
git log --oneline -3
git status --short
```

Clear old build outputs and build release packages (no install, no `+debug`):

```
rm -f OITCore/packages/*.deb OITI/packages/*.deb
cd OITCore
make clean package FINALPACKAGE=1
cd ../OITI
make clean package FINALPACKAGE=1
ls ../OITCore/packages ../OITI/packages
```

Each folder should list one `.deb`. Test those exact files on the phone (with `iproxy 2222 22` running):

```
scp -P 2222 ~/theos-projects/OITUI/OITCore/packages/*.deb ~/theos-projects/OITUI/OITI/packages/*.deb root@127.0.0.1:/var/mobile/
```

On the phone:

```
dpkg -i /var/mobile/com.wilburt.oitcore_*.deb /var/mobile/com.wilburt.oiti_*.deb
sbreload
```

Then check the Island, the settings pages and the sliders. When it all works, publish from the Mac. For `v0.2.0`:

```
git tag -a v0.2.0 -m "OITUI 0.2.0"
git push origin v0.2.0
gh release create v0.2.0 --title "OITUI 0.2.0" --notes-file RELEASE_NOTES_0.2.0.md ~/theos-projects/OITUI/OITCore/packages/*.deb ~/theos-projects/OITUI/OITI/packages/*.deb
```

| Command | What it does | Where |
| --- | --- | --- |
| `git tag -l` | Lists existing tags. | Arch PC, Mac |
| `git show v0.1.0 --stat` | Shows what the v0.1.0 tag points at. | Arch PC, Mac |
| `gh release list` | Lists GitHub Releases. | Arch PC, Mac |
| `gh release view v0.1.0` | Shows the v0.1.0 release and its attached files. | Arch PC, Mac |

Pre-releases (betas). A beta for testers can be built from `experiments` once the work has run on the phone. `OITI/control` says `0.2.0~beta.1` (the tilde sorts it below `0.2.0`), the tag is `v0.2.0-beta.1` and the GitHub Release is marked pre-release. First commit and push the version, docs and code from the Arch PC:

```
cd ~/OITUI
git switch experiments
git status --short
git add -A
git commit -m "OITI 0.2.0 Beta 1: Island Notifications, docs"
git push
git log --oneline -1
```

Then on the Mac, build from that exact commit with a clean tree (the `git status` line must print nothing):

```
cd ~/theos-projects/OITUI
git fetch --prune origin
git switch experiments
git pull --ff-only
git status --short
git log --oneline -1
rm -f OITCore/packages/*.deb OITI/packages/*.deb
cd OITCore
make clean package FINALPACKAGE=1
cd ../OITI
make clean package FINALPACKAGE=1
ls ../OITCore/packages ../OITI/packages
```

The two `git log` hashes must match. Test those exact `.deb` files on the phone (with `iproxy 2222 22` running), the same way as a release (`scp`, `dpkg -i`, `sbreload`), and check section 13 before tagging. Then publish from the Mac, in this order (never tag before the `.deb` files are built and tested from that commit):

```
cd ~/theos-projects/OITUI
git tag -a v0.2.0-beta.1 -m "OITI 0.2.0 Beta 1"
git push origin v0.2.0-beta.1
gh release create v0.2.0-beta.1 --prerelease --title "OITI 0.2.0 Beta 1" --notes-file RELEASE_NOTES_0.2.0-beta.1.md ~/theos-projects/OITUI/OITCore/packages/*.deb ~/theos-projects/OITUI/OITI/packages/*.deb
```

GitHub shows the tilde in the file name as a dot (`0.2.0.beta.1`); `dpkg` uses the version in the package's `control` file. If the tag or release is wrong, delete it with `gh release delete v0.2.0-beta.1 --cleanup-tag --yes` and start again from the build.

## 11. Gotchas

- `defaults delete` does not exist on this phone. Write a value instead (`-int 0`).
- `dumpstate` must be defined again after every new SSH login.
- If a dump seems to do nothing, check `DiagnosticsLevel` first: at level 0 the dump trigger is ignored on purpose.
- The first `make package install` after changing OITCore headers must be in OITCore, before OITI or OITS.
- Never add a trailing `# comment` to a command you paste into the phone.
- `git branch -d` is the safe delete (it refuses unmerged branches). `-D` forces it, so use it only after a squash-merged pull request.
- Releases come from the Mac with `FINALPACKAGE=1`. Packages built on the Arch PC print arm64e ABI warnings and should not be published.
- After a squash merge GitHub deletes `experiments`. Recreate it with the block under "After the merge" before starting new work.

## 12. Status bar layout (red `rdar:45025538` bar) and provider check

Build `0.1.1` (tag `OITI-0.1.1-rc1`) has a **Status Bar Layout** picker at the bottom of OITI's settings page (Automatic, Off, or a named layout). It only acts while the Island is on, and the hooks are off in safe mode. The provider is chosen when a status bar is built, so a changed layout needs a respring. Level 0 writes one `CHOICE` line per distinct provider choice. Level 1 adds a boot report, `LAYOUT`, `PROVIDER` lists and one `LIVE` line per status bar.

| Command | What it does | Where |
| --- | --- | --- |
| `grep -e SESSION -e SAFE /tmp/OITIDebug.log` | Shows the build tag and whether hooks are installed. Look for `READY hooks installed` and no `SAFE MODE`. | Phone |
| `grep CHOICE /tmp/OITIDebug.log` | The provider UIKit chose, what OITI returned and why. Works at level 0. | Phone |
| `grep LEARN /tmp/OITIDebug.log` | Whether this phone recorded its own native provider this launch, or why not. Level 0. † | Phone |
| `cat /var/mobile/Library/Preferences/OITINativeProvider.plist` | The recorded native provider (machine, provider, nativeBounds, os, build, time). Absent until a launch with the Island off has built a status bar. † | Phone |
| `grep STATUSBAR /tmp/OITIDebug.log \| tail -90` | The whole report, including `LIVE`, `LAYOUT` and `PROVIDER` lines. Needs level 1 (`DiagnosticsLevel`, section 5). | Phone |

Wait at least 2 minutes between resprings so the respring-loop guard (section 7) does not trip. If it does, clear it with the `rm` row in section 7 and respring once.

**Someone reports the red bar.**
1. They install the `.deb` and respring once. Automatic is the default.
2. If it is still red or looks wrong: Settings > Insula > Status Bar Layout, pick another layout, tap Respring, wait 2 minutes.
3. They run `grep CHOICE /tmp/OITIDebug.log` and send the output.

**Reading a `CHOICE` line.**
- `UIKit chose X`: the provider iOS picked for this screen. With the Island off this is the device's native provider; write it down. `nil` with the Island on is what the red bar looks like.
- `-> returning Y`: what OITI returned, with the decision text. `auto replaced ...` means OITI substituted the native provider.
- The decision text ends with `[native provider from learned record]`, `[... from table]` or `[... from width guess]`: which source gave the native provider `auto` used.
- To read a device's native provider: set Enable Dynamic Island off, respring, and read the line with `islandEnabled=0` (or read `OITINativeProvider.plist`, which holds the same answer once a launch with the Island off has built a status bar). The table in `OITINativeProviderNameForScreen` in `Tweak.xm` only needs an entry for a device whose log shows something the learned record cannot give.

**Reading a `LEARN` line** (†, build `OITI-exp-2026-10-20-b`). `LEARN recorded: native provider for <machine> is <class>` means the record was written; `LEARN record already holds ...` means nothing changed. `LEARN skipped: ...` says why nothing was recorded: the phone is not in the device table (an iPhone 8 Plus, for example: the line proves the code ran and nothing changes), UIKit chose nil or Fallback, a `UIStatusBarVisualProviderClassName` override is set, the MobileGestalt cache holds the spoofed 2556, or the cache is unreadable. Nothing is recorded in a launch that started with the Island on: turn the Island off, respring once and wait for the Island-off launch to finish building the status bar, then turn it back on. Delete the plist to forget the record (`rm /var/mobile/Library/Preferences/OITINativeProvider.plist`); it is not removed on uninstall.

**To set the layout from a terminal instead of the picker:**

```
defaults write com.wilburt.oiti.prefs StatusBarLayout -string off
```

Valid values are `auto`, `off`, or a `_UIStatusBarVisualProvider_*` class name from the `PROVIDER` lines. The phone's `defaults` has no delete mode, so write `auto` to go back. A wrong class can crash SpringBoard; after 5 launches in 120 s safe mode turns the hooks off, and the red bar returns but the phone stays usable.

## 13. Island Notifications (OITI 0.2.0)

Island Notifications shows each notification banner as an Island element. It is off by default. The switches and sliders are on Settings > Insula > Notifications and write the domain `com.wilburt.oiti.prefs`. Everything except the install lines below needs the Island on (OITI's spoof or real hardware); otherwise the stock banner stays.

| Key | Meaning |
| --- | --- |
| `islandNotificationsEnabled` | Show notifications in the Island (default off). |
| `islandNotificationStackEnabled` | Keep a bounded stack of up to four notices (default on). Off keeps only the newest notice; toggling off clears older visible items. The Settings page warns that this is experimental and unpolished. |
| `islandNotificationsHideBanner` | Fade the stock banner window while the Island element shows (default off). Only acts after the element registered. |
| `IslandNotificationsStyle` | 0 Compact, 1 Wide, 2 Expanded (default). Compact and Wide are experimental. |
| `IslandNotificationsDuration` | Seconds on screen, 2 to 10 (default 4). |
| `IslandNotificationsMessageLines` | Message lines before the ellipsis, 1 to 4 (default 2). |
| `IslandNotificationsCornerExtra` | Points added to the Island's corner radius while a notification shows, -4 to 8 (default 0). |
| `NotificationHaptic` | One short light haptic per banner request (default off). Independent of the other switches. |

### Experimental stack (owner-tested on iPhone 8 Plus / iOS 16.7.16)

The stack keeps up to four notices, oldest to newest. In Expanded/Wide style the newest is the main notice and older notices render as individual rounded compact cards in its secondary content. They still share the outer expanded Island card. In Compact style all notices are compact. A fifth notice evicts the oldest. Each notice has its own timer; its lifetime resets when moved to compact or promoted. Swiping removes that notice, and removing the newest promotes the newest survivor. Tapping opens that notice but leaves its Island item until timeout or swipe. The owner has confirmed the stack appears; timing, overflow and the full interaction matrix still need additional checking.

Regression checklist for a new build:

1. With Expanded selected, send two different notifications close together. Confirm the first becomes Compact and the second is Expanded.
2. Send four, then a fifth. Confirm the oldest disappears and the other four remain in newest-first order.
3. Swipe away the newest and confirm the newest survivor expands. Swipe an older compact item and confirm the others stay in place.
4. Tap a specific notice and confirm it opens the matching conversation/app, remains in the Island, and can still be swiped away.
5. Repeat in Compact style and confirm all four are compact. Check that demoted items receive a fresh visible lifetime.
6. Turn **Stack Multiple Notifications** off while notices are visible. Confirm the newest remains, older items clear, and each new notice replaces the previous one. Then turn Island Notifications off and confirm the stack clears, any hidden stock banner is restored, and new notifications use the stock path.
7. Check `/tmp/OITIDebug.log` for `STACK`, `AUTH`, `TAP`, `SWIPE`, and any `GUARD caught` lines.

The owner tested the current design on iOS 16.7.16, but real Dynamic Island hardware, other iOS builds, Compact/Wide styles and extended timeout behavior remain open. Leave the safe-mode guard enabled and allow two minutes between resprings.

**Reporting a problem (testers).** First raise the log level, wait 2 minutes after the respring (safe mode counts quick launches), trigger one notification, then read the log:

```
defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 1
```

```
sbreload
```

```
grep -E "SESSION|SAFE|NOTIF|ELEMENT" /tmp/OITIDebug.log | tail -80
```

Send that output, plus your device, iOS version and jailbreak. The `NOTIF banner request` lines contain the first characters of your notification titles and messages, so read them before sharing. Afterwards set the level back:

```
defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 0
```

**What a good run looks like.**

| Command | What to look for | Where |
| --- | --- | --- |
| `grep -E "SESSION\|SAFE" /tmp/OITIDebug.log` | The build tag `OITI-0.2.0`, `READY hooks installed` and no `SAFE MODE`. | Phone |
| `grep -E "banner hook\|promotion guard" /tmp/OITIDebug.log` | `banner hook installed on ...` and `promotion guard installed ...` (also at level 0). `NOT installed` plus `CANDIDATES` lines means this iOS version needs a code change. | Phone |
| `grep -E "banner request\|registered\|haptic played" /tmp/OITIDebug.log \| tail` | One `banner request` and one `registered` per notification (level 1); `haptic played` if the haptic is on. | Phone |
| `grep -E "GUARD\|GESTURES\|TOUCH\|TAP\|tap ran\|SWIPE\|open app" /tmp/OITIDebug.log \| tail` | `GESTURES attached` per notification; after a tap `TAP on the notification element` and `tap ran -_executeDefaultAction:` (the fallback lines `tap: no matching stock banner` / `open app` mean the stock banner was already gone); `SWIPE up` after a swipe. A `GUARD caught` line is a bug report. | Phone |

If a notification ever shows as a stock banner with the feature on, check the `ELEMENT` lines: `no SAUISystemApertureManager seen yet`, `missing class` and `element creation is off` are the safe failure paths.

**Developer tools** (need `DiagnosticsLevel` 1; details in `DIAGNOSTICS.md`). Show a test element without a real notification:

```
touch /tmp/OITIPoC.trigger
```

Try different text (title, message, bundle id, subtitle, one per line; empty lines are skipped), for example a long message, no title, or a subtitle:

```
printf 'Alex\nThis is a much longer message to see how the Island handles several lines of text without cutting it off in a bad way, even with a very long word like supercalifragilisticexpialidocious\ncom.apple.MobileSMS\n' > /tmp/OITIPoCSample.txt
```

```
printf '\nOnly a message and no title at all\ncom.apple.MobileSMS\n' > /tmp/OITIPoCSample.txt
```

```
printf 'Alex\nSee you at 7\ncom.apple.MobileSMS\nWeekend Plans\n' > /tmp/OITIPoCSample.txt
```

```
rm -f /tmp/OITIPoCSample.txt
```

Show where each view landed (about 1 s after a test element appears):

```
grep -E "VIEWS|layout variant|GUARD caught" /tmp/OITIDebug.log | tail -12
```

Force a layout variant, ignoring the Style picker (1 compact, 3, 4, 5 expanded, 6 wide; write -1 to turn the override off):

```
defaults write com.wilburt.oiti.prefs IslandNotificationsDevLayout -int 6
```

Stop the Island element from running at all (turn both switches off in settings, or):

```
defaults write com.wilburt.oiti.prefs islandNotificationsEnabled -int 0
```


## 14. Live settings check (builds `OITI-exp-2026-10-21-a` and `-b`)

Color, opacity, outline hiding and the custom banner position now apply while the setting changes, with no respring. The Island has to be on screen to see the first three, so start a timer first (Clock app, or ask Siri for one).

1. Settings > Insula > Color and Opacity. Turn on **Use Custom Color** and drag Red, Green and Blue: the Island background should follow the slider while it moves. Turn the switch off: the Island goes back to black.
2. Turn on **Use Custom Opacity** and drag **Opacity** (the slider used to be labelled "Blue"). The Island should fade and change as you drag, then return to normal when the switch goes off. The same slider also sets the custom color's alpha when Use Custom Color is on.
3. Root page: switch **Disable Island Outline** on and off. The outline should hide and come back live.
4. Settings > Insula > Notifications: turn on **Use Custom Notification Position** and change X and Y. A banner window that already exists moves immediately; otherwise the next banner appears at the new position. Turning the custom position **off** only takes effect on the next banner, because OITI does not know the original frame.

5. Bottom of the main OITI page: the line under the credit should read `OITI version 0.2.0-1+debug` for a debug build, or `0.2.0` for a release package. It comes from the package database (`/var/jb/var/lib/dpkg/status`). If Settings is not allowed to read that file it shows the version taken from `control` at build time with `(built-in)` after it, which for a debug build lacks the `-1+debug` part.

6. Settings > Insula > Scale, **Use Custom Scale** (build `OITI-exp-2026-10-21-b`). The width and height sliders are relative to Apple's size now, so 1.0 is the stock Island. With the switch on and both sliders at 1.0, the Island must look the same as with the switch off, **position included**: turn it on and off and confirm nothing moves. Then change the sliders: below 1.0 shrinks the Island and its content, above 1.0 grows them. **Reset Scale** puts both back to 1.0. Anyone who had Custom Scale on before this build starts at 1.0 (the old values are not carried over).
7. Apple Mode, main page, the switch under **Enable Dynamic Island**. Set a few customizations first (a custom color, Island size 0.65 / 0.70, Use Custom Position, Island Notifications on). Turn **Apple Mode** on: a blue banner appears at the top of every page, and the Island should go back to the stock iOS one without a respring (custom color and size gone, notification stack cleared, banners back to the system banner). **Fix Island Position**, **Enable Dynamic Island**, Status Bar Layout and safe mode must keep working as set. On another page the banner has **Turn Off Apple Mode**. Turn it off and every customization must return exactly as it was. Log lines: `grep -e "Apple Mode" /tmp/OITIDebug.log` shows `PREF Apple Mode ON: ...` and `OFF`.

Check the log (level 1 shows COLOR, level 2 shows TOUCHPASS):

```
grep -e COLOR -e TOUCHPASS -e PREF /tmp/OITIDebug.log | tail -n 20
```

Report anything that only changes after a respring, and anything that fails to return to stock when its switch is turned off.

## 15. Element crash recovery check (build `OITI-exp-2026-10-21-c`)

While an OITI Island element is on screen, `/var/mobile/Library/Preferences/OITILiveElement.plist` exists. If SpringBoard ends while it does, the next launch keeps Island notifications and the startup animation off for 120 seconds and uses the stock banner. Test it by killing SpringBoard on purpose while a notice is showing.

| Command | What it does | Where |
| --- | --- | --- |
| `cat /var/mobile/Library/Preferences/OITILiveElement.plist` | The breadcrumb: time, pid, reason, build. Present only while an element is live. | Phone |
| `grep RECOVERY /tmp/OITIDebug.log` | The recovery decisions. Level 0. | Phone |
| `killall -9 SpringBoard` | Simulates a crash. | Phone |

Steps:

1. Settings > Insula > Notifications: turn **Island Notifications** on and set the duration to 15 seconds. Make sure Apple Mode is off.
2. Over SSH, confirm the breadcrumb is absent: `cat /var/mobile/Library/Preferences/OITILiveElement.plist` should say no such file.
3. Type `killall -9 SpringBoard` in the SSH session but do not press Enter. Make a notification arrive (a message from another device, or a timer). While the Island notice is showing, press Enter. In a second SSH session you can also check that the breadcrumb exists during the notice.
4. After the respring, wait for the Island and log in again: `grep RECOVERY /tmp/OITIDebug.log | tail -n 5` should show `RECOVERY the previous SpringBoard ended while an OITI Island element was live`, and no breadcrumb file should exist.
5. Within 120 seconds, make another notification arrive. It must appear as the **stock banner**, and the log should show `RECOVERY: notification is not shown as an Island element (N s left)`. Everything else in OITI (position, size, color) keeps working.
6. After 120 seconds, a new notification must be an Island notice again, and the log shows `RECOVERY window is over`.
7. Negative check: with a notice on screen, use OITI's own **Respring** button. The log should say `RECOVERY not needed: SpringBoard was restarted from OITI's settings`, and the first notification afterwards must be an Island notice at once.
8. Check that a normal notice that expires on its own leaves no breadcrumb: wait for it to disappear, then `cat` the file again (no such file).

Note: a respring from anywhere other than OITI's settings while a notice is on screen (`sbreload`, another tweak) also counts as a dirty exit and opens the window. That is expected and costs only 120 seconds of stock banners.

## 16. Download progress check (builds `OITI-exp-2026-10-21-d` to `-j`)

Stage 1 has one source, a simulated download (stage 2 adds App Store downloads and the percentage-only look: section 18). Settings > Insula > **Download Progress** has the switch, the two return-to-idle limits, the test size and the Start and Stop buttons. Everything is off by default, and Apple Mode hides it.

| Command | What it does | Where |
| --- | --- | --- |
| `grep DOWNLOAD /tmp/OITIDebug.log` | Start, finish, limit and removal decisions. Level 0. | Phone |

Steps:

1. Turn on **Show Download Progress**, leave both limits on Never, set the test size to 800 MB, tap **Start Test Download**. With Style **Minimal** (the default; OITI's own pill since build `-h`, matched to the Island since `-j`) a black pill should grow from the top of the Island, starting at the Island's own top edge and centered on it, with the Island's height kept empty at the top (like the expanded Island's sensor row) and, under it, as the owner designed it: the header `App Store - Test Download` centered; the downloaded size centered above the bar; the row with the speed on the left of the bar, the rounded blue bar in the middle and the percentage on the right; and the total size centered under the bar. An unknown total shows `?` and an unknown percentage `…`. The numbers update about twice a second, with the speed drifting between about 2 and 28 MB/s. **Settings > Insula > Download Progress > Minimal Size** has **Width**, **Bottom padding** and **Move up or down** sliders that apply while the pill is showing. Play music or start a timer first and check that the pill still covers the Island completely and lines up with its top edge. The log says how the Island was found: `grep DOWNLOAD /tmp/OITIDebug.log | tail -n 6` shows `island={{x, y}, {w, h}} (the Island's pill view (N candidates) | computed from the stock size ...) -> pill={...}`. If the pill's top edge does not line up with where the Island is, send that line and what you see, or use **Move up or down** meanwhile. Swipe the pill up to dismiss it. If no pill appears at all (build `-h` showed nothing), run `grep DOWNLOAD /tmp/OITIDebug.log | tail -n 15` and send the output. Build `-i` creates the pill's window in the Island's own window scene and writes `progress pill up for ...` plus two `pill shown:` and `pill 0.8 s later:` lines with the window's hidden flag, scene, level, whether the pill is in that window, its alpha and its frame, which says exactly why it is or is not on screen. If even `test download started` is missing from the log, the Start button never reached SpringBoard (check for a safe-mode banner or Apple Mode). **The bar must stay on screen well past your Island Notifications duration**: in build `-d` it disappeared after about that many seconds because the system's own alert timer ended it and OITI was never told. Leave the test running for a full minute and watch.
2. Let it finish: the bar turns green with `Download complete · 800 MB` for about 3 seconds, then the Island returns to idle. Check the compact state too (for example, open an app so the Island shows compact): it should show the app icon and a percentage.
3. Return to idle by size: set **After this much is downloaded** to 100 MB and start a test. At about 100 MB the Island should go idle and the log should say `limit reached (... downloaded)`. The download carries on in the background. Tap Start again after Stop: the bar returns.
4. By time: set the size limit back to Never, **After this long on screen** to 20 s, start a test. The Island should go idle after 20 seconds.
5. Swipe the bar up: it must go away and stay away until the next Start. Tapping **Start Test Download** while the test is still running counts as a next start and brings the bar back.
6. **Stop Test Download** while the bar is up: it should disappear at once.
7. Switch **Show Download Progress** off during a test: the bar goes. Switch it back on: it returns, because the test is still running. Do the same with **Apple Mode**.
8. With Island Notifications on, let a notification arrive during a test. Note what happens (the download should become a compact card or be replaced, depending on the stack setting; see the known limits in `OVERVIEW.md`) and report anything odd.
9. Crash check: during a test run `killall -9 SpringBoard`. After the respring there is no bar (the test lives in memory), and the log should show the element recovery line from section 15.

10. Settings no longer crash when a choice is picked (the Style picker here, **Style** on the Notifications page and **Status Bar Layout** on the main page all crashed Settings before, because the choice row kept its label and its specifier under one key). Pick a value in each and confirm Settings stays open and shows the new choice. Then switch **Style** to Detailed during a test: the bar should be replaced by the larger one with the name "Test Download" and a line like `212 MB of 800 MB · 9.4 MB/s`. Switch back to Minimal.
11. If the bar ever disappears on its own, `grep DOWNLOAD /tmp/OITIDebug.log` should show `the progress element left the screen after N s but nothing in OITI removed it, so the system ended it (drop 1 of 5)`, and the bar comes back after 1.5 s (then 4.5, 13.5 and 30 s on later drops, and it stops after five). Report that line and its time.

Report: layout problems (clipped text, bar too tall or too short), a speed or size that looks wrong, anything that stays on screen after Stop, and any stutter in other Island animations while the bar updates.

## 17. Install progress dump (build `OITI-exp-2026-10-24-c`)

Download Progress stage 2, step 1: a read-only dump of what SpringBoard exposes about a real install. It does not change anything on screen and needs `DiagnosticsLevel` 1. Line format and how to read it: `DIAGNOSTICS.md`, "OITI install progress dump". The output carries the tag `INSTALL`.

Set up once. Turn Auto-Lock off for the test (Settings > Display & Brightness > Auto-Lock > Never) so the screen stays on while the samples run, and keep the phone on the Home Screen page that shows the downloading icon.

| Command | What it does | Where |
| --- | --- | --- |
| `defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 1` | Turns dumps on. | Phone |
| `sbreload` | Applies it. Wait about 10 seconds afterwards. | Phone |
| `defaults write com.wilburt.oiti.prefs InstallDumpSamples -int 6` | Samples after the snapshot (default 6, 0 to 30). | Phone |
| `defaults write com.wilburt.oiti.prefs InstallDumpIntervalSeconds -float 2` | Seconds between samples (default 2, 1 to 10). | Phone |
| `defaults write com.wilburt.oiti.prefs InstallDumpCallGetters -bool true` | Second pass only: also call declared property getters of private objects. Default off; build `-a` crashed SpringBoard calling methods by name. Leave it off for the first runs. | Phone |

Define the helper once per SSH login. It is forgotten when you log out, so define it again after reconnecting (a respring alone does not end your session). It writes a label into the log and asks for one install dump:

```
installdump() { echo "$(date '+%m-%d %H:%M:%S') [MARK] $1" >> /tmp/OITIDebug.log; touch /tmp/OITIInstallDump.trigger; }
```

One run takes the snapshot at once and then the samples, so about 12 seconds with the defaults. Wait for `=== END` before the next run and before collecting the log (a log collected mid-run is missing the samples):

```
grep INSTALL /tmp/OITIDebug.log | tail -n 3
```

Runs, in this order. Use a big app (1 GB or more) so the download lasts. The `sleep 15;` form gives you time to go back to the Home Screen after pressing Enter; make sure the downloading icon is visible on the page you are on.

| Command | Phone state | Where |
| --- | --- | --- |
| `installdump idle-nothing-installing` | Nothing downloading. A baseline to compare against. | Phone |
| `sleep 15; installdump appstore-downloading-early` | An App Store download is running, a few percent in, icon visible on the Home Screen. | Phone |
| `sleep 15; installdump appstore-downloading-later` | The same download, 20 percent or more further on. | Phone |
| `sleep 15; installdump appstore-paused` | Tap the icon on the Home Screen to pause the download first. Resume it afterwards. | Phone |
| `sleep 15; installdump appstore-installing` | Optional: the last moments, when the icon says Installing. | Phone |

Later, the same way (use the label to say what it is): `appstore-update-downloading` for an app update (start it from the App Store Updates tab) and `testflight-installing` for a TestFlight install.

Collect the result. The first command pulls out the useful lines; the second copies the file to the PC (it contains the names of the apps being installed, so read it before sharing):

```
grep -e MARK -e INSTALL /tmp/OITIDebug.log > /tmp/OITIInstall.txt
```

```
scp -P 2222 root@127.0.0.1:/tmp/OITIInstall.txt ~/Downloads/OITIInstall.txt
```

For a short paste instead of the file (the verdicts and sample summaries only):

```
grep -e MARK -e "INSTALL.*VERDICT" -e "INSTALL.*SUMMARY" -e "INSTALL.*PROGRESS " /tmp/OITIDebug.log | tail -n 80
```

Other greps:

| Command | What it shows | Where |
| --- | --- | --- |
| `grep "INSTALL.*CANDIDATE" /tmp/OITIDebug.log` | The apps, placeholders and icons that look like an install. | Phone |
| `grep "INSTALL.*CLASSPROBE" /tmp/OITIDebug.log` | Which guessed classes exist and their progress-related methods. | Phone |
| `grep "INSTALL.*ICONVIEW" /tmp/OITIDebug.log` | The Home Screen icon views that report progress. | Phone |
| `grep "INSTALL.*HINT" /tmp/OITIDebug.log` | Says when no icon views were found (wrong page, or Home Screen not showing). | Phone |
| `grep "INSTALL.*ERROR" /tmp/OITIDebug.log` | Any exception the dump caught. | Phone |

If a run prints nothing, check `DiagnosticsLevel` first (`install dump request ignored` appears only for the notification, and the trigger file does nothing at level 0), then `grep SESSION /tmp/OITIDebug.log | tail -n 2`. When you are done, set the level back with `defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 0` and run `sbreload`. A second class query on whatever the dump finds works as before (section 6: put the class names in `/tmp/OITIClassQuery.txt`, then `dumpstate classq-X`).

## 18. App Store downloads and the percentage-only look (build `OITI-exp-2026-10-26-a`; the App Store source was checked on the device with `-25-a` except TestFlight, the Cancelled state and the check animation are new and untested)

Download Progress stage 2. Settings > Insula > **Download Progress** has a new group, **App Store Downloads**, with **Show App Store Downloads**. It needs **Show Download Progress** on too. Both are off by default, Apple Mode switches them off and safe mode never starts the source. App Store downloads report a percentage only (the install dump found no byte counts), so the bar shows the percentage and an estimate of the time left, and no sizes or speed. Section 17 is the read-only dump this was designed from.

| Command | What it does | Where |
| --- | --- | --- |
| `defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 1` then `sbreload` | Level 1 logs the App Store source (tracking, pause, finish). | Phone |
| `grep DOWNLOAD /tmp/OITIDebug.log \| tail -n 40` | The source and tracker lines (`DIAGNOSTICS.md`, "OITI App Store download source"). | Phone |
| `defaults write com.wilburt.oiti.prefs DownloadTestFractionOnly -bool true` then `sbreload` | Developer key: **Start Test Download** reports a whole-percent fraction only, to try the percentage-only look without a real download. `-bool false` and `sbreload` go back to bytes. | Phone |

Steps:

1. Percentage-only look with the test download. Turn on `DownloadTestFractionOnly` (above), leave the size limit on Never, tap **Start Test Download**. Minimal: header `App Store - Test Download`, `Downloading` above the bar, the percentage on the right, nothing on the left, and under the bar `~N s left` (it appears after the percentage has moved a few times). Detailed: a line like `42% · ~1 min left`. At the end the Minimal text fades into a green check (Detailed: `Download complete`); stop it with **Stop Test Download** instead and the bar turns red with `Cancelled` for a moment. The **size** limit does nothing in this mode (set it to 100 MB and check); the **time** limit works. Turn the key off and confirm the byte look is unchanged.
2. A real App Store download. Turn on **Show Download Progress** and **Show App Store Downloads**, set DiagnosticsLevel 1, start a new install of a large app (1 GB or more) and stay on the Home Screen. Within about a second the bar should appear with the header `App Store - <app name>`, `Downloading`, a percentage that rises in whole steps and an estimate after a few steps. The log should show `App Store source on`, then `tracking <bundle ID> (<name>) at N% (installPhase=... installState=... ...)`.
3. Pause: tap the downloading icon to pause. The bar should say `Paused` with no estimate. The log shows `paused at N% (...)`: please report that line, its `progressPaused` and `placeholderPaused` values tell which one reflects a pause. If neither changes the bar will not say Paused and the number just stops; report that too. Resume: `resumed`, and `Downloading` again.
4. The end: let it finish. Expect the completion animation in the Minimal look (the text fades, the bar contracts into a green circle and a white check is drawn in it, about 0.8 s; with Reduce Motion on it appears at once) or `Download complete` in Detailed, held for about 3 seconds, then the Island returns to idle, and the log shows `left the placeholder list at N%: complete (app installed: yes)`. Report how long it took from the last percentage change to that line (the earlier dump saw the fraction sit at 76 percent while the install phase changed).
5. Cancel: start another download and cancel it (press and hold the icon, Cancel Download, or remove the placeholder). After the 3 s grace the bar turns red with `Cancelled` for about 1.6 s and then goes (Detailed: `Download cancelled`), and the log says `cancelled (app installed: no)`. Switching the feature or the source off mid-download still removes the bar at once (the log says `dropped`).
6. An app update (Updates tab) and a TestFlight install: report whether the bar appears. If it does not, run the install dump (section 17) with the labels `appstore-update-downloading` and `testflight-installing`: an update of an installed app may not be a placeholder at all.
7. Two downloads at once: the header reads `2 downloads` (checked; any count above one reads `N downloads`) with the mean percentage.
8. Switch **Show App Store Downloads** (and then **Show Download Progress**, and **Apple Mode**) off during a download: the bar goes and nothing crashes; on again, it returns while the download is still running.

Report: a bar that never appears (and the `DOWNLOAD` lines), a wrong percentage compared with the icon's ring, an estimate that is far off or jumps, anything that stays on screen after the download is gone, and any respring.
