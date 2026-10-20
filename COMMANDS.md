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

Deliberately trip the guard (†). This fakes four recent launches, so the next respring is the fifth:

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
tar -xzf "$(ls -t ~/Downloads/oitui-*.tar.gz | head -n 1)" -C ~/OITUI
```

```
tar -xzf "$(ls -t ~/Downloads/oitui-*.tar.gz | head -n 1)" -C ~/theos-projects/OITUI
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
| `grep STATUSBAR /tmp/OITIDebug.log \| tail -90` | The whole report, including `LIVE`, `LAYOUT` and `PROVIDER` lines. Needs level 1 (`DiagnosticsLevel`, section 5). | Phone |

Wait at least 2 minutes between resprings so the respring-loop guard (section 7) does not trip. If it does, clear it with the `rm` row in section 7 and respring once.

**Someone reports the red bar.**
1. They install the `.deb` and respring once. Automatic is the default.
2. If it is still red or looks wrong: Settings > OITI > Status Bar Layout, pick another layout, tap Respring, wait 2 minutes.
3. They run `grep CHOICE /tmp/OITIDebug.log` and send the output.

**Reading a `CHOICE` line.**
- `UIKit chose X`: the provider iOS picked for this screen. With the Island off this is the device's native provider; write it down. `nil` with the Island on is what the red bar looks like.
- `-> returning Y`: what OITI returned, with the decision text. `auto replaced ...` means OITI substituted the native provider.
- To read a device's native provider: set Enable Dynamic Island off, respring, and read the line with `islandEnabled=0`. Add it to `OITINativeProviderNameForScreen` in `Tweak.xm`.

**To set the layout from a terminal instead of the picker:**

```
defaults write com.wilburt.oiti.prefs StatusBarLayout -string off
```

Valid values are `auto`, `off`, or a `_UIStatusBarVisualProvider_*` class name from the `PROVIDER` lines. The phone's `defaults` has no delete mode, so write `auto` to go back. A wrong class can crash SpringBoard; after 5 launches in 120 s safe mode turns the hooks off, and the red bar returns but the phone stays usable.

## 13. Island Notifications (OITI 0.2.0)

Island Notifications shows each notification banner as an Island element. It is off by default. The switches and sliders are on Settings > OITI > Notifications and write the domain `com.wilburt.oiti.prefs`. Everything except the install lines below needs the Island on (OITI's spoof or real hardware); otherwise the stock banner stays.

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

