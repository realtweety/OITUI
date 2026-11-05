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

Makes the Island itself smaller or larger while its contents keep their normal size. Only the width and height multipliers of Apple's `sensorRegionSize` are used (the experiments showed it is the root input; the other sizes follow from it). 1.0 is Apple's own size. Changes apply immediately, with no respring. You can also set these on the Settings > Insula > Scale page (Island Size sliders). Keep "Use Custom Scale" turned off while judging the result.

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

Since batch 2 (build `OITI-exp-2026-11-02-a`, reported working on the phone; the loop-trip check was not itemized) the guard records the launch and decides before `preferencesChanged()`, so a crash inside the preference reload now trips safe mode too; the commands and log lines on this page are unchanged. Safe mode also shows as a banner at the top of every OITI settings page, with a **Clear Safe Mode & Respring** button (`experiments` build `OITI-exp-2026-10-20-a`). A respring started from OITI's own Respring button or that button is not counted as a possible crash: the guard logs `respring requested from OITI settings N s ago: launch not counted, history cleared`. A respring from anywhere else (`sbreload`, another tweak, Dopamine) still counts.

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

Releases are created only from tested work on `main`. Build on the **Mac**, ship OITCore and OITI together, and do not ship OITS until it is verified. The current release is `v0.2.5` (OITI package version `0.2.5`; OITCore remains `0.1.0`).

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

Then check the Island, the settings pages and the sliders. When it all works, publish from the Mac. For `v0.2.5`:

```
git tag -a v0.2.5 -m "OITUI 0.2.5"
git push origin v0.2.5
gh release create v0.2.5 --title "OITUI 0.2.5" --notes-file RELEASE_NOTES_0.2.5.md ~/theos-projects/OITUI/OITCore/packages/*.deb ~/theos-projects/OITUI/OITI/packages/*.deb
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
- Every OITI source file must be listed in `OITI_FILES` in `OITI/Makefile`. A file that is missing from the list builds fine but fails at link time with undefined symbols (the `Diagnostics/` files are listed there since the split's round 1).

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
| `NotificationTapDismisses` | Settings > Insula > Notifications > Dismiss When Tapped (default off). A tap on a notification notice removes it 0.25 s after the tap. Not for the Hello or a download. Off under Apple Mode. |

### Experimental stack (owner-tested on iPhone 8 Plus / iOS 16.7.16)

The stack keeps up to four notices, oldest to newest. The newest is the Island notification in the chosen Style; the older notices are small cards of their own below the Island (build `OITI-exp-2026-11-03-d`; before that they were compact cards inside the newest notice's card). A fifth notice evicts the oldest. Each notice has its own timer; its lifetime resets when moved to compact or promoted. Swiping removes that notice, and removing the newest promotes the newest survivor. Tapping opens that notice but leaves its Island item until timeout or swipe (unless Dismiss When Tapped is on). The owner has confirmed the stack appears; timing, overflow and the full interaction matrix still need additional checking.

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
2. Turn on **Use Custom Opacity** and drag **Opacity** (the slider used to be labelled "Blue"). The Island should fade and change as you drag, then return to normal when the switch goes off. (Before build `OITI-exp-2026-11-01-a` the same slider also set the custom color's alpha; the color is now always opaque, see section 20.)
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

## 18. App Store downloads and the percentage-only look (build `OITI-exp-2026-10-26-a`; the App Store source, the Cancelled state and the Minimal look's check animation have been checked on the owner's phone; TestFlight is not confirmed and the Detailed look has no completion check yet)

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

## 19. Module split checks (v0.3.0, one per round)

Each round of the `Tweak.xm` split is built and checked on its own before the next one starts. Behavior must not change, so the check is: it builds, nothing looks different, and the module's own features still work. The build tag stays `OITI-exp-2026-10-26-a` during the split, so tell builds apart by the `[MARK]` lines below.

Before building, run the mechanical check from the repo root (it needs only `python3` and `git`, no phone). `--old HEAD` compares with the last commit, so run it before committing the round; after the commit use `--old HEAD~1`. If several rounds are ever left uncommitted, `HEAD` stays at the last commit, so the check covers every round since then and needs one `--allow-wrapper NAME` for each `%init` wrapper added in those rounds (so far `OITIInstallIslandSizeHooks`, `OITIInstallResearchHooks`, `OITIInstallDiagnosticHooks` and `OITIInstallStatusBarHooks`). It must print `RESULT: OK`:

```
cd ~/OITUI
python3 tools/check_split.py --old HEAD
```

Optional extra check (Logos syntax and hook count): `git clone https://github.com/theos/logos ~/logos`, then add `--logos ~/logos/bin/logos.pl`.

Build and install (Arch PC; section 3 has the Mac version). Run `make clean package` first if the build prints errors about missing files: every source file must be listed in `OITI_FILES` in `OITI/Makefile`.

```
cd ~/OITUI/OITI
make clean package
THEOS_DEVICE_IP=localhost THEOS_DEVICE_PORT=2222 make package install
```

### Round 1: Diagnostics (files in `OITI/Diagnostics/`)

Level 0 (normal install). Nothing may look different and no dump machinery may run:

```
echo "$(date '+%m-%d %H:%M:%S') [MARK] round1-level0" >> /tmp/OITIDebug.log
sbreload
```

Wait 15 seconds, then:

```
sed -n '/round1-level0/,$p' /tmp/OITIDebug.log | grep -E 'SESSION|CHECK|DUMP|STATUSBAR|trigger polling'
```

Expected: `SESSION` lines ending in `READY hooks installed`, `CHECK` lines, no `trigger polling started` and no `DUMP` lines. Stock look, banners and Settings pages as before.

Level 1 (dumps on):

```
defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 1
echo "$(date '+%m-%d %H:%M:%S') [MARK] round1-level1" >> /tmp/OITIDebug.log
sbreload
```

Wait 15 seconds, then:

```
sed -n '/round1-level1/,$p' /tmp/OITIDebug.log | grep -E 'trigger polling started|STATUSBAR (BEGIN|END)|BEGIN #|END #'
```

Expected: `trigger polling started`, then `STATUSBAR BEGIN reason=boot` and `STATUSBAR END reason=boot`, then an `auto-baseline` dump (`=== BEGIN #1 reason=auto-baseline ===` and its `END`) a few seconds after the Island first lays out.

The dump trigger, the install dump trigger, the Darwin notification and the test element (define `dumpstate` and `installdump` first, sections 6 and 17):

```
dumpstate round1-dump
sleep 4
touch /tmp/OITIPoC.trigger
sleep 4
installdump round1-install
sleep 20
notifyutil -p com.wilburt.oiti/Dump
sleep 4
sed -n '/round1-dump/,$p' /tmp/OITIDebug.log | grep -E 'reason=|=== (BEGIN|END)'
```

Expected: a `trigger-file` dump (`BEGIN #2` to `END #2`), a hello element on the Island for a few seconds, an `INSTALL` run `=== BEGIN #1 reason=trigger-file ... ===` through its `END`, and a `darwin-notification` dump. Then compare one dump with an older one: `grep -c METRICS /tmp/OITIDebug.log` should be well above zero and the `METRICS multiplier` line should show your Island size settings.

Back to normal:

```
defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 0
sbreload
```

Report: a build error (the first lines of it), a missing expected line above, a dump that never starts, or anything on screen that looks different from before the split.

### Round 2: DownloadProgress (files in `OITI/DownloadProgress/`)

Run the check and the build from the top of this section. The full download checks are sections 16 and 18; this is the short version. Settings > Insula > **Download Progress** has the switches. Nothing may look or behave differently from before the split.

1. Switch **Show Download Progress** off (the default). Open the Download Progress page and the Style picker: no crash, and the Island looks stock.
2. Switch it on, Style **Minimal**, test size 800 MB, tap **Start Test Download**. The black pill appears under the Island, the bar runs with speed, size and percentage, and at the end it turns into the green check and goes away.
3. Start another test and swipe the pill up: it goes and stays away. **Start Test Download** while it runs brings it back. **Stop Test Download** removes it at once.
4. Style **Detailed**, start a test: an Island element with the app icon, the headline and the bar with its text line; at the end it turns green with `Download complete`, then the Island returns to idle.
5. Switch **Show Download Progress** off during a test (the bar goes), on again (it returns); the same with **Apple Mode**.
6. Switch **App Store Downloads** on. Start a real App Store download (a small free app): the percentage follows the App Store's. Pause it, resume it, cancel a second one, let a third finish. Each ends the way section 18 describes.
7. With Island Notifications on and Style **Detailed**, send a notification during a test download: the stack behaves as before the split.

```
grep DOWNLOAD /tmp/OITIDebug.log | tail -30
```

Expected: `DOWNLOAD started`, `progress element up` (Detailed) and `finished` or `cancelled` lines for each run above, and no `the system ended it` line.

Report: a build error (the first lines), a step above that behaves differently from before the split, or a crash or respring.

### Round 3: IslandSize (file in `OITI/IslandSize/`)

Run the check (`python3 tools/check_split.py --old HEAD --allow-wrapper OITIInstallIslandSizeHooks`) and the build from the top of this section. This module is the Island's position, size, scale and appearance, so a visual pass is the check: for each step, compare with how it looked before the split. Settings > Insula, main page unless a page is named.

1. Every setting at its default (or **Apple Mode** on): the Island looks stock, and a banner drops from the stock position.
2. **Scale** page, **Island Size**: drag **Island Width** and **Island Height**; the Island resizes live without a respring and returns to stock at 1.0 (**Reset Island Size to 1.0**).
3. **Scale** page, **Custom Island Scale**: switch on **Use Custom Scale** and drag **Width (X)** and **Height (Y)**; the whole Island scales around Apple's own size and returns at 1.0 (**Reset Width and Height to 1.0**).
4. **Fix Island Position** on and off. Then **Custom Island Positioning**: **Use Custom Position** with **X Position:** and **Y Position:**, and **Save**.
5. **Notifications** page: **Fix Notification Positioning**, then **Custom Notification Positioning** (**Use Custom Notification Position**, X and Y, **Save**). Send yourself a notification; the banner appears where the setting says.
6. **Color and Opacity** page: **Use Custom Color** with Red, Green and Blue, and **Use Custom Opacity**. Both apply live and switch off cleanly. Main page, **Misc**: **Hide When Not in Use** and **Disable Island Outline**, each on and off.
7. **Apple Mode** on: every customization above is off; the built-in position and notification fixes stay.

```
echo "$(date '+%m-%d %H:%M:%S') [MARK] round3" >> /tmp/OITIDebug.log
sbreload
sleep 15
sed -n '/round3/,$p' /tmp/OITIDebug.log | grep -E 'SESSION|CHECK|ERROR|WARN'
```

Expected: `SESSION` lines ending in `READY hooks installed`, and no new `ERROR` or `WARN` lines.

Report: a build error (the first lines), a step above that behaves differently from before the split, or a crash or respring.

### Round 4: IslandNotifications (files in `OITI/IslandNotifications/`)

Run the check and the build from the top of this section (`python3 tools/check_split.py --old HEAD --allow-wrapper OITIInstallResearchHooks --allow-wrapper OITIInstallDiagnosticHooks`). This is the biggest module, so the check is longer. Settings > Insula > **Notifications**; section 13 has the details.

1. Switch **Show Notifications in the Island** on, Style Expanded. Run the regression checklist of section 13, steps 1 to 6: two notifications close together, four and then a fifth, swipe the newest and an older one, tap one (it opens the matching app and stays swipeable), Compact style, **Stack Multiple Notifications** off and on, Island Notifications off (the stack clears, new notifications use the stock banner).
2. **Hide the Stock Banner** on: the stock banner fades while the Island element shows; off: it comes back. Check **Notification Haptic**, the duration, the message lines and the roundness slider once each.
3. Section 15 (crash recovery): steps 1 to 3 and the negative check in step 7 (OITI's own Respring does not start the 120 second window).
4. Detailed download with a notification: start a test download in the Detailed look, send a notification; the stack behaves as before the split.
5. Level 1 (`DiagnosticsLevel` 1, `sbreload`): `touch /tmp/OITIPoC.trigger` shows the test element, and one real notification logs `AUTH` lines (the diagnostic hook group).

```
grep -E 'STACK|AUTH|TAP|SWIPE|GUARD caught|RECOVERY|banner request|registered' /tmp/OITIDebug.log | tail -40
```

Expected: the same kinds of lines as before the split (`banner request` and `registered` per notification, `TAP` after a tap, `SWIPE` after a swipe, `AUTH` at level 1) and no `GUARD caught`.

Report: a build error (the first lines), a step above that behaves differently from before the split, or a crash or respring.

### Round 5: Startup (file in `OITI/Startup/`)

Run the check and the build from the top of this section (`python3 tools/check_split.py --old HEAD`; no `--allow-wrapper` is needed, this round adds no `%init` wrapper). Settings > Insula > **Startup Animation**.

1. Switch **Enable Hello Animation (Prototype)** on, then `sbreload`. Unlock and stay on the Home Screen: the Hello clip plays once in the Island, muted, and the Island element disappears when it ends.
2. Cooldown: `sbreload` again within five minutes, the animation does not play; after five minutes it does.
3. Gate: `sbreload`, stay on the Lock Screen; nothing plays until you unlock onto the Home Screen. Open an app right after unlocking: the animation does not appear over it.
4. Interruption: start a charging activity or a call, or send a notification while it plays; the card yields to it (`yielding startup card` in the log).
5. Toggle off: the setting stops it at the next respring; switching it off while it plays removes the element.

```
grep -E 'HELLO' /tmp/OITIDebug.log | tail -30
```

Needs `DiagnosticsLevel` 1 (`HELLO` lines are level 1). Expected: `waiting`/`created muted, single-play video view`/`startup prototype presented`, or the `suppressed by five-minute cooldown` and `yielding startup card` lines in steps 2 and 4.

Report: a build error (the first lines), a step above that behaves differently from before the split, or a crash or respring.

### Round 6: StatusBar (file in `OITI/StatusBar/`)

Run the check and the build from the top of this section (`python3 tools/check_split.py --old HEAD --allow-wrapper OITIInstallStatusBarHooks`). Settings > Insula > **Status Bar Layout**; section 12 has the details. The 8 Plus runs the provider code inert, so the check is that nothing changed:

1. After the install and `sbreload`, the status bar looks stock: no red `rdar:45025538` bar, clock, signal and battery in place, with the Island on and off.
2. Settings > Insula > Status Bar Layout: switch between Automatic and Off, respring each time; the status bar stays normal.
3. Respring-loop guard (section 7): safe mode still turns the status bar hooks off (no `CHOICE` lines in safe mode).

```
grep -E 'CHOICE|STATUSBAR|SESSION' /tmp/OITIDebug.log | tail -20
```

Expected: one `CHOICE` line per distinct combination (level 0), `READY hooks installed`, and at `DiagnosticsLevel` 1 the `LIVE` lines from the status bars.

Report: a build error (the first lines), a status bar that looks different, or a crash or respring.

### Round 7: Shared and core (files in `OITI/Shared/` and `OITI/Safety/`)

Run the check and the build from the top of this section (`python3 tools/check_split.py --old HEAD --allow-wrapper OITIInstallStatusBarHooks`; this round adds no `%init` wrapper). The round moves the shared state, the preferences reload, the respring-loop guard and the startup self-check, so it touches everything and the check covers the whole tweak.

1. Stock settings (every Island setting at its default) still look stock; banners and the settings pages open and save.
2. Live settings: change the Island color, transparency and relative scale in Settings > Insula; the Island follows without a respring. Change a Download setting and a Notifications setting once each (section 14).
3. Respring-loop guard and safe mode (section 7): the loop test still ends in safe mode with the banner on the Settings page; **Clear Safe Mode & Respring** brings the hooks back.
4. Self-check: with the Island on, `grep CHECK /tmp/OITIDebug.log` shows `OK spoof state matches islandEnabled`.
5. Apple Mode on and off; the Hello animation, a notification in the Island and a test download each work once.

```
grep -E 'SESSION|GUARD|SAFE|CHECK|PREF' /tmp/OITIDebug.log | tail -30
```

Expected: `READY hooks installed`, `OK spoof state matches islandEnabled`, a `CHANGED` line at `DiagnosticsLevel` 1 when you change a setting, and in the loop test the `GUARD` lines that lead to safe mode.

Report: a build error (the first lines), a setting that no longer applies live, safe mode not engaging or not clearing, or a crash or respring.

### Round 8: shared runtime helpers (file `OITI/Shared/OITIRuntimeHelpers.xm`)

Run the check and the build from the top of this section (`python3 tools/check_split.py --old HEAD --allow-wrapper OITIInstallStatusBarHooks`). The round moves eight getter helpers that three modules and the install dump call, so the check is that each caller still works:

1. Hello animation: switch **Enable Hello Animation (Prototype)** on, `sbreload`, unlock; it plays once (it uses `OITISafeObject` and `OITISafeBool` for the lock and Home Screen checks).
2. Island notifications: a notification shows in the Island with title, message and app name (uses `OITISafeString`); tapping it still opens the app (uses `OITIKVCObject`).
3. Download progress: **Show Download Progress** with the App Store source on, start a real App Store download; the Island follows it (uses the install helpers).
4. Install dump (needs `DiagnosticsLevel` 1): `touch /tmp/OITIInstallDump.trigger`, then `grep -c INSTALL /tmp/OITIDebug.log` is above 0.

Report: a build error (the first lines), a step that behaves differently from before the split, or a crash or respring.


## 20. v0.3.0 polish checks (one block per stage; build tag in the heading)

### Stage 1: colour alpha and Settings footers (build `OITI-exp-2026-11-01-a`; owner reports it works, checks not itemized)

Changes: Use Custom Color now always sets an opaque color; **Use Custom Opacity** and its **Opacity** slider are the only transparency control (applied once). The Settings page builder no longer drops a footer on a group with no rows after it (the Scale page's "Island Size" footer). The Color and Opacity page gained two footers. No setting was added or removed, no default changed.

1. Settings > Insula > Color and Opacity. Start a timer so the Island is on screen. Turn **Use Custom Color** on, pick a clearly visible color and leave **Use Custom Opacity** off. Set **Opacity** to 0.3: the Island must stay fully opaque in that color (before this build it went see-through).
2. Turn **Use Custom Opacity** on with Opacity at 0.3: the Island becomes see-through once (compare with Custom Color off: the same strength of fade, not a double fade). Opacity 1.0 looks the same as switching Use Custom Opacity off. Turn both off: the Island is stock black.
3. Read the two footers on that page (under Use Custom Opacity's slider and under Use Custom Color's switch): they must say the color is opaque and that changes apply immediately. Check that this is true.
4. Settings > Insula > Scale. Under the **Island Size** heading there must now be a small grey paragraph ("Makes the Island itself smaller or larger...") before **Island Width**. The other footers on the page (Custom Island Scale, Width (X), Height (Y)) are unchanged.
5. Quick pass over the other pages (Root, Notifications, Download Progress, Startup Animation): layout and footers look as before.
6. Level 1 `COLOR` lines: `background ... -> ...` should show alpha 1 for the applied color. Build tag in the log header: `OITI-exp-2026-11-01-a`.

Static check on the Mac or PC: `python3 tools/check_settings.py` (lists groups whose footer is shown under the header; currently only Scale > Island Size, as intended).

### Batch 1: Apple Mode haptic, position settings, device documentation (build `OITI-exp-2026-11-01-b`, run as part of the `-c` fix build; owner reports it works, checks not itemized)

Changes: Notification Haptic is off under Apple Mode (new global `sNotificationHapticEnabled`, forced off with the other customizations). The four position fields (Island X/Y, banner X/Y) are parsed strictly and limited to one screen, in Settings and again in the tweak; the Y Position default shown is 20.5 (the code default). The Save buttons check every field and show "Saved". Fix Notification Positioning shows the same "No built-in offsets / Estimated offsets" notice as Fix Island Position. Footers now say what applies immediately, from the next notification, or after a respring. Nothing in the device table changed; see `DEVICES.md`. Stage 1 (above) is included.

**Feature 1: Apple Mode haptic.** Level 1 log on (`defaults write com.wilburt.oiti.prefs DiagnosticsLevel -int 1`).
1. Settings > Insula > Notifications: **Notification Haptic** on, **Show Notifications in the Island** off. Send yourself a notification: one light tap.
2. Settings > Insula, **Apple Mode** on. Send another: no tap, stock banner. The log shows `PREF CHANGED ... NotificationHaptic: 1 -> 0` (the snapshot is the effective value) and no `haptic played` line.
3. Apple Mode off again, no respring: the tap is back.
4. While Apple Mode is on, the blue banner on the Notifications page names the notification stack and the haptic as saved but not applied and says Fix Notification Positioning still applies; on the main page it says Fix Island Position and Status Bar Layout still apply. Read the Apple Mode footer on the main page: it lists the haptic and the stack.
5. Stack behavior is unchanged: with Apple Mode off, Island Notifications on and **Stack Multiple Notifications** on, a burst of three still stacks as before.

**Feature 2: position settings.**
6. Settings > Insula, Custom Island Positioning. In **Y Position:** type `abc`, tap elsewhere: an alert says it is not a number and the previous value is shown again. Type `20,5`: stored and shown as `20.5`. Type `99999`: an alert states the limit (one screen, in points; for X the screen width, for Y the screen height) and the field shows the limit. Clear the field: it shows `20.5` (Y) or `0` (X). The notifications page does the same for **X Position:** / **Y Position:** (defaults `0` and `40`).
7. With **Use Custom Position** on, the Island follows each accepted value immediately. Tap **Save** with the keyboard open: the field commits, the button reads "Saved" for about a second. Tap it again with no keyboard: same.
8. Strict-parser check from the PC (replace the notify command if yours differs): `defaults write com.wilburt.oiti.prefs yPos -string nan`, then `notifyutil -p com.wilburt.oiti/PrefsChanged`. With Use Custom Position on, the Island stays at Y 20.5 and the level 1 log says `PREF position yPos = nan is not a plain number, using 20.5`. Repeat with `-string 1e30` (same line) and `-float 5000` (`outside the allowed range, using 1000.0`; the Island then sits at the one-screen limit, which is applied when the position is used). Restore with `defaults delete com.wilburt.oiti.prefs yPos`.
9. Notifications page: turn **Fix Notification Positioning** on. On a device without a table entry (the 8 Plus) the alert "No built-in offsets" must appear, as it does for **Fix Island Position** on the main page. Read the new footer.
10. Footers: check each claim once. **Disable Island Outline** (immediately, timer on screen), **Hide When Not in Use** (respring; turning it off needs one), **Duration**, **Message Lines**, **Roundness**, **Style** and **Haptic** (from the next notification), custom banner position (a banner on screen moves at once; switching it off applies to the next banner). Report any footer that is wrong; the Fix Island Position and Hide When Not in Use curtain wording is from the code only, not from a device check.
11. The main page's Misc card now ends after the two toggles; the page links (Startup Animation ... Scale) are in their own card.

**Feature 3: devices.** No phone check for the table (nothing was added). When you run the protocol in `DEVICES.md` section 4, `python3 tools/measure_device.py <log>` has only been tested on synthetic lines so far; tell me if it fails on a real log.

**Regression pass.** Section 20 (Stage 1), stock settings look stock, the respring-loop guard (section 7) and a Download Progress test download with Apple Mode off.

### Bootloop fix: safe first run of build `OITI-exp-2026-11-01-c`

Background: the first batch 1 build hung SpringBoard at startup (see `OVERVIEW.md`, "batch 1 bootloop fix"). This build removes the suspected cause but has not run on the phone. Treat it as untrusted until it has booted once.

Before you install:
1. Keep the recovery path you already used: Dopamine > Settings > Tweak Injection off, jailbreak, then remove or disable OITI. Rename-to-disable is faster than uninstalling: `mv /var/jb/Library/MobileSubstrate/DynamicLibraries/OITI.plist /var/jb/Library/MobileSubstrate/DynamicLibraries/OITI.plist.off` (the filter plist is what makes the tweak load).
2. Keep a copy of the last good package (`OITI 0.2.5`) on the PC.
3. Collect the evidence of the earlier failure first, if it still exists (it decides whether the fix is the real cause): `ls -lt /var/mobile/Library/Logs/CrashReporter | head -20` and `grep -l OITI /var/mobile/Library/Logs/CrashReporter/*.ips` (a `SpringBoard-*.ips` that lists `OITI.dylib` and a backtrace through `preferencesChanged` / `OITIReadPositionPreference` / `UIScreen` confirms the cause; no report at all suggests a hang rather than a crash). Also `cat /var/mobile/Library/Preferences/OITIBootLog.plist` and `ls /var/mobile/Library/Preferences/OITISafeMode.plist`: no launch entries from the failed attempts means the crash happened before the guard ran. Send me what you find. This is read-only; nothing here changes the phone.

Install and first run:
4. Build: `cd ~/OITUI/OITI && make clean package` (no `install`). Check that it is the new build: `strings "$(find .theos -name OITI.dylib | head -n 1)" | grep OITI-exp-2026-11-01-c` must print the tag.
5. Copy it over with `scp`, then `dpkg -i` it on the phone. Do NOT respring yet.
6. Disable it first and respring once without it, to prove the install did no harm: `mv .../OITI.plist .../OITI.plist.off` then `sbreload`. SpringBoard must come back normally.
7. Open a second SSH session and run `tail -F /tmp/OITIDebug.log` in it. In the first session: `mv .../OITI.plist.off .../OITI.plist`, then `sbreload`.
8. Within about 15 seconds SpringBoard must be back and the log must show `SESSION START build=OITI-exp-2026-11-01-c` followed by `SESSION READY hooks installed`. If the screen does not return after a minute, do not keep forcing reboots (each launch counts toward the loop guard and only helps if the guard gets to run); use the recovery path in step 1 and collect the crash report as in step 3.
9. If it boots: run `python3 tools/check_ctor_path.py` and the Batch 1 and Stage 1 device checks above, in that order. Check 6 and 8 (position fields and the `defaults write` cases) now exercise the one-screen limit at use time, which is new code that has not run on a device.

### Batch 2: loop guard order, Detailed download protection, promotion-guard notice, cleanup (build `OITI-exp-2026-11-02-a`; owner reports it works, checks not itemized)

Changes: see `OVERVIEW.md`, "batch 2". Compile-checked for arm64 iOS 16.5 off the phone (Logos plus clang, no link); the guard logic was also run through a Python mirror (`python3 tools/guard_model.py`, a mirror of the logic, not the Objective-C) and `python3 tools/check_ctor_path.py` passes. The off-device compile check is `tools/offline_check.sh`. Reported working on the phone by the owner (general report, 2026-11-02).

Safe first run (same recovery path as before: Dopamine > Tweak Injection off, jailbreak, then rename `OITI.plist` to `OITI.plist.off`). Keep a second SSH session on `tail -F /tmp/OITIDebug.log`.

**Feature 1: loop guard.**
1. Normal boot: the log shows `SESSION START build=OITI-exp-2026-11-02-a`, then `GUARD SpringBoard launches in the last 120 s: 1 (trip at 5)`, then `PREF initial` lines (level 1) and `SESSION READY`. The GUARD line must come BEFORE the first PREF line (it used to come after).
2. Respring from Settings > Insula > Respring: `GUARD respring requested from OITI settings N s ago: launch not counted, history cleared`, no `TRIPPED`.
3. Real loop still caught: run `sbreload` over SSH five times, about 10 seconds apart. The fifth launch logs `SAFE TRIPPED`, then `SESSION SAFE MODE`, and the settings pages show the orange banner. Tap Clear Safe Mode & Respring: the changes return.
4. In safe mode, `cat /var/mobile/Library/Preferences/OITIBootLog.plist` shows the launches, the log has no `PREF initial` line (the full preference reload is skipped there), and changing a setting does nothing (as before).
5. Optional, only if you want proof of the new coverage: this needs a deliberately failing build, so skip it unless you want to; the logic was checked off the phone only.

**Feature 2: Detailed download and the guard notice.**
6. Settings > Insula > Download Progress: Look Detailed, Show Download Progress on. Start the test download. While it runs, send yourself notifications (Island Notifications on, stack on): the download is no longer removed. Send four or more: the oldest notification is evicted, the download stays. The log shows `STACK full ... evicting oldest` (level 1) and no `progress element removed (capacity)`.
7. Turn Stack Multiple Notifications off and send a notification during the test download: the download stays beside the newest notice (two items), and a second notification replaces the first notification only. Report what the compact download card looks like and whether its percentage keeps updating while a notification is the newest item.
8. When the notification leaves, the download element comes back to its expanded look. Swiping the download away or Show Download Progress off still removes it for the rest of that download (unchanged).
9. Promotion-guard notice. This cannot be provoked on purpose. If you ever see `ELEMENT GUARD element creation is now OFF until the next respring` in the log, open Settings > Insula: a yellow "Island elements are switched off" banner with a Respring button must be at the top of every page, and gone after a respring. To only see the banner, create the file by hand: `printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>time</key><real>1788300000</real><key>failures</key><integer>5</integer></dict></plist>' > /var/mobile/Library/Preferences/OITIElementsOff.plist`, reopen Settings > Insula, then respring (the new launch deletes the file).

**Feature 3: cleanup.**
10. At DiagnosticsLevel 0 (`defaults delete com.wilburt.oiti.prefs DiagnosticsLevel`, respring), send two notifications: the log shows no `our element before layout values`, `our element parts` or `registered` lines. At level 1 they are back.
11. Settings > Insula > Startup Animation: the group and the switch no longer say "Prototype"; the main page header reads "Status Bar (Experimental)". The Hello animation itself behaves as before.

**Regression pass.** Section 20 Stage 1 and Batch 1 checks, the position fields and Apple Mode haptic, a normal notification burst with stacking on, and a test download with the Minimal look.


### Batch 3: Hello +0.5 s, Settings text and order, Dismiss When Tapped (build `OITI-exp-2026-11-03-a`; compile-checked only, not device-tested)

Changes: see `OVERVIEW.md`, "batch 3". Compile-checked for arm64 iOS 16.5 off the phone with `tools/offline_check.sh` (Logos plus clang, no link; `check_ctor_path.py` and `check_settings.py` pass). The %ctor and the launch path are untouched, so the normal safe first run is enough; keep a second SSH session on `tail -F /tmp/OITIDebug.log`. Recovery if anything misbehaves is the usual one (Dopamine > Tweak Injection off, then rename `OITI.plist`).

**Hello +0.5 s.** (Settings > Insula > Startup Animation > Enable Hello Animation on, Enable Dynamic Island on; set `DiagnosticsLevel` to 1 for the log lines, then respring and wait 10 s plus the unlock.)
1. The log shows `SESSION START build=OITI-exp-2026-11-03-a`. After unlocking the Hello plays: the word draws in, holds, fades; then the Island stays open and empty black for about half a second longer than before, then closes. Compare with the previous build if you can: the only visible difference is the black pause at the end. Report whether the pause reads as intended.
2. Log order: `HELLO video playback started`, then `HELLO video reached end; holding the last frame 0.5 s before removing the startup element`, then about 0.5 s later `ELEMENT STACK removed ... reason=video-finished remaining=0`. Total on screen about 6.8 s.
3. Settings > Insula > Notifications > Island Notification Duration at the minimum (2 s) and at 4 s (default): respring (wait out the five-minute cooldown between runs) and confirm the Hello still plays to the end and does not close at 2 s or 4 s. Then the same at the maximum (10 s).
4. Interruption still works: with Show Notifications in the Island on, send yourself a notification while the Hello plays (also try during the last half second, while the black frame is held): the Hello is cancelled (`HELLO ... cancel`/`STACK removed ... reason=...`), the notice shows, and no second removal line appears for the Hello afterwards. Plugging in the charger does not remove it (charging is kept behind the animation, as before).
5. Compact style (unverified): Settings > Insula > Notifications > Style Compact, Show Notifications in the Island on, respring and let the Hello play. Report whether it still shows the full expanded card as it does at Expanded. Put Style back to Expanded afterwards if you prefer.
6. Tap on the Hello (not changed): it opens the Settings app. Tell me whether it should do nothing instead.

**Settings text and order.**
7. Settings > Insula > Notifications: the first group is Island Notifications (Show Notifications in the Island, Hide the Stock Banner), then Experimental Notification Stack, then Island Notification Style, Tapping a Notification, Haptics and the rest. Every switch keeps its saved value.
8. Settings > Insula > Startup Animation and Download Progress: the footers now say what applies immediately and what needs a respring. Check each claim you can: Show Download Progress and Show App Store Downloads on and off during a test download (applies at once), Style Minimal to Detailed during a download (the bar is replaced at once), a Return to Idle limit changed while a bar is showing (applies to it), the test download size (applies on the next start). Report any footer that is wrong.

**Dismiss When Tapped.**
9. Default (off): send yourself a notification with Island Notifications on; tap it. It opens the app and the notice stays until the timeout or a swipe up (as before).
10. Settings > Insula > Notifications > Dismiss When Tapped on (no respring): send another and tap it. It opens the app and the notice leaves the Island shortly after. The log shows (level 1) `ELEMENT TAP dismisses the notification element ...` then `STACK removed ... reason=tap`.
11. With the stack on, send three notifications, tap the newest: only that notice goes and the next one is promoted. Tap on a notice that is already compact (an older one) and report what happens.
12. During a test download (Look Detailed) a tap on the download card does not remove it. A tap on the Hello is unchanged.
13. Apple Mode on: Island notifications are off as before; the Apple Mode banner on the Notifications page lists Dismiss When Tapped. The log shows `PREF CHANGED ... NotificationTapDismisses: 1 -> 0` (effective value).

**Regression pass.** Section 20 Stage 1, Batch 1 and Batch 2 checks, a normal notification burst with stacking on, a test download with both looks, and the respring-loop guard (section 7).

### Batch 4: Hello 0.25 s hold, Hello tap to Insula, return to idle by percentage, Detailed completion check (build `OITI-exp-2026-11-03-b`; compile-checked only, not device-tested)

Changes: see `OVERVIEW.md`, "batch 4". Compile-checked for arm64 iOS 16.5 off the phone with `tools/offline_check.sh`; `check_ctor_path.py` and `check_settings.py` pass. The %ctor and the launch path are untouched, so the normal safe first run is enough (second SSH session on `tail -F /tmp/OITIDebug.log`; recovery is the usual one). Set `DiagnosticsLevel` to 1 for the log lines.

**Hello hold and tap.** (Settings > Insula > Startup Animation > Enable Hello Animation on, Enable Dynamic Island on; respring, wait 10 s and unlock; the five-minute cooldown applies between runs.)
1. The log shows `SESSION START build=OITI-exp-2026-11-03-b`. The Hello plays; after the fade the black card stays about a quarter of a second, then closes. Log: `HELLO video reached end; holding the last frame 0.25 s ...`, then `STACK removed ... reason=video-finished`. Report whether 0.25 s feels right.
2. Tap the Hello while the word is on screen (not in the first second): Settings opens directly on Insula's page, not on the Settings main list. Log: `ELEMENT TAP on the startup animation ...`, `open url prefs:root=Insula via openURL:options:completionHandler:`, then `STACK removed ... reason=tap`. The Hello is gone when you come back to the Home Screen (it does not keep playing).
3. Tap it during the black hold at the end: same result, and no second removal line for it afterwards.
4. Interruptions still work as in batch 3 (a notification while it plays cancels it; the charger does not).

**Return to idle by percentage.** (Settings > Insula > Download Progress: Show Download Progress on; the new slider **After this percentage is reached** is in the Return to Idle group between the size and the time limits, default Never.)
5. Set it to 50 %, Style Minimal, **Start Test Download** (a size of 200 MB or more is easiest to watch). At 50 % the pill goes away, the log says `limit reached (50% downloaded): the Island returns to idle, the download carries on`, and the download keeps going. **Stop Test Download**, **Start Test Download** again: the bar returns. Repeat with Style Detailed.
6. With `DownloadTestFractionOnly` on (the percentage-only look, `COMMANDS.md` above): the same limit works with no sizes. If you have an App Store download to hand, the real App Store source is the most useful check: set 50 % and watch the Island return to idle at about half.
7. Changing the slider while a bar is showing applies to it at once: with the bar at 30 % set the limit to 20 % and the Island goes idle on the next tick; set it back to Never during a new download and the bar stays to the end.
8. Never (0) behaves exactly as before: the bar stays until completion, the size limit and the time limit still work (section 18 step 3).

**Detailed look completion check.** (Style Detailed.)
9. Let a test download finish (a small size, about 20 MB). In the trailing slot (right of the headline) the percentage is replaced by a small green circle with a white check that is drawn; the bar is green and the line under it says `Download complete`; about 3 s later the element goes. Report how the badge looks: size, position, whether anything is cut off. Log: `DOWNLOAD Detailed look: completion check shown in the trailing slot (label {...})` (please send me that line if the badge looks wrong).
10. With Reduce Motion on (Settings > Accessibility > Motion) the badge appears at once with the check already drawn.
11. Start another test during the 3 s after a completion: the percentage text is back and no check remains. **Stop Test Download** mid-download: `Download cancelled`, no check.
12. Minimal look unchanged: its own check inside the pill still plays at completion.

**Regression pass.** Section 20 Batch 3 checks, a notification burst with stacking on, and the respring-loop guard (section 7).

### Batch 5, round 1: Stack Look "Separate Cards" (build `OITI-exp-2026-11-03-c`; superseded by round 2 below, which removed the Stack Look setting; kept for history)

Changes: see `OVERVIEW.md`, "batch 5 round 1". New setting: Settings > Insula > Notifications > **Stack Look** (Inside the Island = default, Separate Cards). The %ctor and launch path are untouched, so the normal safe first run is enough (second SSH session on `tail -F /tmp/OITIDebug.log`; recovery is the usual one). Set `DiagnosticsLevel` to **2** for this round, because the level 2 `STACKCARDS` probe lines are what I need if the cards sit wrong; send me the `STACKCARDS` lines (and the `ELEMENT STACK` lines) from `/tmp/OITIDebug.log` after steps 2 to 4.

1. Default unchanged: with Stack Look on Inside the Island, send three notifications quickly (Island Notifications and the stack on): the older ones are small cards inside the newest notice's card exactly as in batch 4. Log `STACK separate-cards ...`.
2. Settings > Insula > Notifications > Stack Look > Separate Cards (no respring). Send three notifications about a second apart, Style Expanded. The Island shows only the newest notification (its card is now just that one); after a moment two small black capsules fade in under it, the most recent past notice first: app icon on the left, "Title: message" centred, "now" on the right. Report: where they sit relative to the Island's card (gap, width, centred or not), whether they appear while the Island is still growing, and anything cut off. Log: `STACKCARDS refresh: 2 older notices as cards`, `cards shown: 2 under island {...}`.
3. Same with Style Wide and then Style Compact (Compact is unverified: say whether Apple shows anything else for the older notices there).
4. Tap one of the cards: it opens that notice's app (the exact conversation only if the stock banner is still alive or the notification has a URL: tell me which it did) and the other cards are untouched; the tap never opens the newest notice. With Dismiss When Tapped on, the tapped card goes. Swipe up on a card: only that notice goes.
5. Let time pass: the newest expires, the next notice is promoted into the Island and the cards below recompute (one fewer); the card's time text changes from "now" to "1m" after a minute. Notice any flicker or jump.
6. Island Size / Position: change the Island sliders (Settings > Insula > Island Size) and repeat step 2 at a small and a large size, and with the notification position fix on: the cards must stay under the Island's card.
7. Stack Look back to Inside the Island with cards on screen: the cards go and the in-card compact cards return at once. Apple Mode on: no cards, no stack (as before).
8. Landscape / lock screen: the cards must not show in landscape; lock-screen-only deliveries still bypass the banner path (as before).
9. Regression pass: Section 20 Batch 4 checks (Hello tap to Insula, percentage limit, Detailed check), a normal notification burst with Inside the Island, the respring-loop guard (section 7).

### Batch 5, round 2: the stack is the separate cards only (build `OITI-exp-2026-11-03-d`; compile-checked only, not device-tested)

Changes: see `OVERVIEW.md`, "batch 5 round 2". The Stack Look setting is gone and the older notices are always drawn as the cards you tested in round 1. The %ctor and launch path are untouched, so the normal safe first run is enough. `DiagnosticsLevel` 1 is enough now (2 only if the cards sit wrong).
1. Settings > Insula > Notifications: the stack group has only **Stack Multiple Notifications (Experimental)** (no Stack Look row); its footer describes the cards.
2. Send four notifications in a burst (the SSH script, or real ones), Style Expanded: the Island shows only the newest notification; the older ones appear as cards below it exactly as in round 1. The Apple card of the newest notice has no compact cards inside it any more (it never had with Separate Cards on, so nothing should look different from your last test).
3. Style Wide and Compact: the same.
4. Tap a card with a **real** notification (for example a message from another phone, or a Messages or Mail one): tell me whether it opens that exact notification (the conversation or message) or only the app. With a test notification from the SSH script it can only launch the app.
5. A running Detailed download while notices arrive: the Detailed element behaves as in batch 4 when it is the newest; when a notice becomes newest the download is simply not shown as a card (this is the one visible difference to the removed look, where it was a compact card with a text line). The Minimal pill is unaffected.
6. Stack off (Stack Multiple Notifications off): only one notice at a time and no cards. Apple Mode on: no Island notifications and no cards. Respring-loop guard (section 7) and a normal single notification as regression.

### Tool: four test notifications over SSH (shuffled order, random gaps)

Posts four test notices through the developer trigger (`DiagnosticsLevel` at least 1; the trigger file is polled once a second, so the gaps cannot be shorter than about 1.6 s). They go straight into the stack (so they exercise the stack and the cards), not through the stock banner path: no haptic, no stock banner to hide, and a tap on a card can only launch the app (no request). Paste into a `bash` or `zsh` shell on the phone (it needs `$RANDOM`):

```sh
for n in $(for i in 1 2 3 4; do echo "$RANDOM $i"; done | sort -n | cut -d' ' -f2); do
  case $n in
    1) t="Alex";     m="Are we still on for tonight?";  b=com.apple.MobileSMS ;;
    2) t="Calendar"; m="Standup starts in 10 minutes";  b=com.apple.mobilecal ;;
    3) t="Mail";     m="Your order has shipped";        b=com.apple.mobilemail ;;
    4) t="Mom";      m="Call me when you get a chance"; b=com.apple.MobileSMS ;;
  esac
  printf '%s\n%s\n%s\n' "$t" "$m" "$b" > /tmp/OITIPoCSample.txt
  touch /tmp/OITIPoC.trigger
  d=$((160 + RANDOM % 90)); sleep $((d / 100)).$(printf %02d $((d % 100)))
done
```

The four arrive in a random order over about 5 to 7.5 s. The last sample stays in `/tmp/OITIPoCSample.txt` and is reused by a plain `touch /tmp/OITIPoC.trigger`; `rm /tmp/OITIPoCSample.txt` restores the default test text. If `sleep` rejects decimals, use `sleep 2`. For the exact-notification tap use REAL notifications.
