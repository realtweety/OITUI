#!/usr/bin/env python3
"""Summarise one phone's Insula log for the device-measurement protocol (DEVICES.md).

Reads a copy of /tmp/OITIDebug.log written at DiagnosticsLevel 1 or higher and prints only what the log actually says:
the machine identifier and screen, whether the device table has an entry, the Island window frames seen with every
Island customization off (fix=0 pos=0 scale=0), and the banner window frames Apple asked for (BANNER ... in=).
It does not decide, estimate or suggest any offset. A row for OITI/OITIDeviceProfiles.h is built by a person from
measured values (see DEVICES.md, "Adding a row"); nothing printed here is a table entry.

Usage: python3 tools/measure_device.py ~/Downloads/OITIDebug.log
"""
import re, sys

if len(sys.argv) != 2:
    sys.exit(__doc__)
lines = open(sys.argv[1], errors="replace").read().splitlines()

def first(pattern):
    rx = re.compile(pattern)
    for l in lines:
        m = rx.search(l)
        if m:
            return m
    return None

builds = sorted({m.group(1) for l in lines for m in [re.search(r"(OITI-exp-\d{4}-\d{2}-\d{2}-\w+|OITI-\d[\w.~-]*)", l)] if m})
env = first(r"\[DUMP\]\s+ENV build=(\S+) machine=(\S+) os=(.*?) screen=(\{\{.*?\}\}) scale=([\d.]+)")
if not env:
    env = first(r"\[STATUSBAR\]\s+BEGIN reason=\S+ build=(\S+) machine=(\S+) os=(.*?) islandEnabled")
screen = first(r"\[STATUSBAR\]\s+SCREEN bounds=(\{\{.*?\}\}) nativeBounds=(\{\{.*?\}\}) scale=([\d.]+) nativeScale=([\d.]+)")
table = first(r"\[STATUSBAR\]\s+TABLE (no entry for \S+|.*? verified=\d)")
levels = first(r"SESSION.*")

print("== Identity (from the log) ==")
print("build tag(s) in log :", ", ".join(builds) or "none found")
if env:
    print("machine / iOS       :", env.group(2), "/", env.group(3).strip())
else:
    print("machine / iOS       : not found (was DiagnosticsLevel 1 or higher and a dump taken?)")
if screen:
    print("screen bounds       :", screen.group(1), " nativeBounds:", screen.group(2), " scale:", screen.group(3), "/", screen.group(4))
print("device table        :", table.group(1) if table else "not found")

print("\n== Island window frames with every customization off (fix=0 pos=0 scale=0) ==")
rx = re.compile(r"\[ISLAND\]\s+(\S+)@\S+ changed: frame=(\{\{.*?\}\}) bounds=(\{\{.*?\}\}) xf=(\[.*?\]) fix=(\d) pos=(\d) scale=(\d)")
seen = []
for l in lines:
    m = rx.search(l)
    if m and m.group(5) == "0" and m.group(6) == "0" and m.group(7) == "0":
        key = (m.group(1), m.group(2), m.group(3), m.group(4))
        if key not in seen:
            seen.append(key)
for cls, frame, bounds, xf in seen[:8]:
    print(f"{cls}: frame={frame} bounds={bounds} xf={xf}")
if not seen:
    print("none (turn Apple Mode on, keep Fix Island Position off, respring, show a timer, then trigger a dump)")

print("\n== Banner window: frames Apple asked for (BANNER setFrame in=, no override) ==")
rb = re.compile(r"\[BANNER\]\s+(\S+)@\S+ setFrame in=(\{\{.*?\}\}) used=(\{\{.*?\}\}) ov=(\d)")
banners = []
for l in lines:
    m = rb.search(l)
    if m and m.group(4) == "0":
        key = (m.group(1), m.group(2))
        if key not in banners:
            banners.append(key)
for cls, frame in banners[:8]:
    print(f"{cls}: in={frame}")
if not banners:
    print("none (keep both notification position options off and receive a real banner)")

print("\nNothing above is a table entry. See DEVICES.md for how a verified row is made.")
