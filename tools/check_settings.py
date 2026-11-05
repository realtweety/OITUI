#!/usr/bin/env python3
"""Static checks for the Settings plists of Insula (OITI/OITIPrefs/Resources).

Currently checks footer placement: the page builder
(-[OITIBaseListController oiti_buildSettingsPage]) attaches a group's
footerText to the card that follows the group. A group that has a footerText
but is directly followed by another group (or by the end of the list) has no
card to hold it. The builder shows such a footer under the group's header, so
this script only reports them (INFO) to make sure it is deliberate.

Usage: python3 tools/check_settings.py        (run from the repo root)
Exit status 1 only for real problems (a footer on a group with no label and no rows).
"""
import plistlib, glob, os, sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "OITI", "OITIPrefs", "Resources")
problems = 0
for path in sorted(glob.glob(os.path.join(root, "*.plist"))):
    name = os.path.basename(path)
    try:
        data = plistlib.load(open(path, "rb"))
    except Exception:
        continue
    items = data.get("items") if isinstance(data, dict) else None
    if not items:
        continue
    for i, item in enumerate(items):
        if item.get("cell") != "PSGroupCell" or not item.get("footerText"):
            continue
        nxt = items[i + 1] if i + 1 < len(items) else None
        has_rows = nxt is not None and nxt.get("cell") != "PSGroupCell"
        if has_rows:
            continue
        label = item.get("label")
        if label:
            print(f"INFO  {name}: group '{label}' has a footer and no rows; shown under its header")
        else:
            print(f"ERROR {name}: group #{i} has a footer, no label and no rows: nothing can show it")
            problems += 1
print("footer check:", "problems found" if problems else "ok")
sys.exit(1 if problems else 0)
