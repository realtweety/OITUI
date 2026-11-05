#!/usr/bin/env python3
"""Static guard: no UIKit class-method calls on the SpringBoard launch path of OITI.

The tweak's %ctor runs while SpringBoard is still loading its libraries, before UIKit and the main screen exist. It calls
preferencesChanged(), which lives in Shared/OITIPreferences.xm. v0.3.0 batch 1 added a [UIScreen mainScreen] call there (through a
static inline function in a header) and SpringBoard never came back up (a bootloop). Nothing on that path may touch
UIScreen, UIDevice or UIApplication; do that later, from a hook, a layout pass or a dispatch_after block.

This script starts from the files the %ctor path is made of, follows their quoted #import "..." headers (project headers only),
strips comments, and reports class-method sends to UIKit singletons. It cannot see through function pointers or runtime lookups,
and it is a guard against repeating one mistake, not a proof that the launch path is safe.

It also checks the order of the respring-loop guard inside the %ctor (OITIGuardBeginLaunch, OITIEvaluateLoopGuard, then
preferencesChanged()). On the v0.2.5 baseline that order check is expected to fail, because the guard used to run last.

Usage (repo root): python3 tools/check_ctor_path.py       Exit status 1 when something is found.
"""
import os, re, sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "OITI")
START = ["Tweak.xm", "Shared/OITIPreferences.xm", "Shared/OITIState.xm", "Safety/OITISafety.xm"]
BAD = re.compile(r"\[\s*(UIScreen|UIDevice|UIApplication|UIWindow|UIView|UIViewController)\s+[A-Za-z_]"
                 r"|\[\s*OITDeviceInfo\s+(isFullScreenDevice|hasDynamicIsland)\b")

def strip(text):
    text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)

seen, hits = set(), []
def scan(rel):
    path = os.path.normpath(os.path.join(ROOT, rel))
    if path in seen or not os.path.exists(path):
        return
    seen.add(path)
    text = strip(open(path, errors="replace").read())
    for n, line in enumerate(text.split("\n"), 1):
        if BAD.search(line):
            hits.append((os.path.relpath(path, ROOT), n, line.strip()))
    for m in re.finditer(r'#\s*import\s+"([^"]+)"', text):
        inc = m.group(1)
        cand = os.path.join(os.path.dirname(rel), inc)
        scan(cand if os.path.exists(os.path.join(ROOT, cand)) else inc)

for f in START:
    scan(f)
for f, n, line in hits:
    print(f"LAUNCH PATH UIKit call: OITI/{f}:{n}: {line}")

# Order inside the %ctor (v0.3.0 polish, batch 2): the loop guard must record the launch and decide BEFORE preferencesChanged(),
# otherwise a crash inside preferencesChanged() leaves no trace and safe mode can never trip.
order_ok = True
tweak = strip(open(os.path.join(ROOT, "Tweak.xm"), errors="replace").read())
ctor = tweak[tweak.index("%ctor"):]
pos = {name: ctor.find(name) for name in ("OITIGuardBeginLaunch(", "OITIEvaluateLoopGuard(", "preferencesChanged()")}
if min(pos.values()) < 0:
    print("CTOR ORDER: cannot find", [k for k, v in pos.items() if v < 0], "in the %ctor of Tweak.xm")
    order_ok = False
elif not (pos["OITIGuardBeginLaunch("] < pos["OITIEvaluateLoopGuard("] < pos["preferencesChanged()"]):
    print("CTOR ORDER: the %ctor must call OITIGuardBeginLaunch(), then OITIEvaluateLoopGuard(), then preferencesChanged()")
    order_ok = False
bad = hits or not order_ok
print("launch-path check: checked", len(seen), "files;", "FAILED" if bad else "ok", "(UIKit calls:", len(hits), "| %ctor order:", "ok" if order_ok else "wrong", ")")
sys.exit(1 if bad else 0)
