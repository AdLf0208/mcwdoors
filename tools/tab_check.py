#!/usr/bin/env python3
"""Check that the mcwdoors creative tab lists the carried items.

Reads the game's merged content cache
(`<game>/.horizon-cache/mod-content/creative-inventory.json`), prints the tab
ids and the mod's own tab, and fails with the missing ids or a wrong count.
Called by tools/e2e.sh.

Usage: tab_check.py <creative-inventory.json> <expected-count> <id>...
"""
import json
import sys


def main():
    path, expected, *wanted = sys.argv[1:]
    expected = int(expected)
    with open(path) as handle:
        inventory = json.load(handle)
    tabs = inventory.get("tabs", [])
    print("tabs:", [tab.get("id") for tab in tabs])
    ours = [tab for tab in tabs if str(tab.get("id", "")).startswith("mcwdoors:")]
    for tab in ours:
        print("mcwdoors tab:", tab.get("id"), tab.get("title"))
    if not ours:
        print(f"FAIL: no mcwdoors tab in {path}", file=sys.stderr)
        return 1
    listed = [item for tab in ours for item in tab.get("items") or []]
    ids = [entry for entry in listed]
    missing = [item for item in wanted if not any(f'id:"{item}"' in entry for entry in ids)]
    for item in missing:
        print(f"FAIL: the mcwdoors tab misses {item}", file=sys.stderr)
    if missing:
        return 1
    if len(listed) != expected:
        print(
            f"FAIL: the mcwdoors tab lists {len(listed)} items, expected {expected}",
            file=sys.stderr,
        )
        return 1
    print(f"PASS: the mcwdoors tab lists all {expected} items, sampled {len(wanted)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
