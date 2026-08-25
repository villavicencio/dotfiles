#!/usr/bin/env python3
"""One-time repair for a ~/.claude/settings.json that predates the copy-seed scheme.

Two fixes, both idempotent — safe to re-run, and a no-op once applied:

1. Undo a resurrected legacy top-level `allowedTools` key. When both it and
   `permissions.allow` exist, the LEGACY KEY WINS and permissions.allow is
   silently inert — rules sit there looking active while nothing consults them.
   PR #127 consolidated onto permissions.allow; this machine's live file had
   regrown allowedTools with 18 rules against a permissions.allow of 1.
   Folds allowedTools into permissions.allow (dedup, order-preserving) and
   deletes the legacy key.

2. Register the herdr blank-state hook on SessionStart + UserPromptSubmit, so a
   pane that has been /clear'd reads "blank" in herdr's agent sidebar. Fresh
   machines get this from the seeded baseline instead (see
   install_claude_settings.sh); this covers a machine that already had a
   settings.json and so was never seeded.

Run it on any machine whose settings.json predates 2026-08-25. Writes a
timestamped backup first and parse-checks before replacing.

NOTE: Claude Code's auto-mode classifier blocks agents from writing this file
(by design — it stops an agent widening its own permissions), so this is a
human-run script. Invoke it yourself:

    python3 helpers/migrate_claude_settings.py
"""
import collections
import json
import os
import shutil
import sys
import time

SETTINGS = os.path.expanduser("~/.claude/settings.json")
HOOKS = [
    ("SessionStart", "~/.claude/hooks/herdr-blank-state.sh start"),
    ("UserPromptSubmit", "~/.claude/hooks/herdr-blank-state.sh clear"),
]


def main():
    if os.environ.get("DOTFILES_DRY_RUN", "0") == "1":
        print("[dry-run] would repair %s (allowedTools fold + blank-state hooks)" % SETTINGS)
        return 0
    if not os.path.exists(SETTINGS):
        print("No settings at %s — nothing to migrate." % SETTINGS)
        return 0

    try:
        data = json.load(open(SETTINGS), object_pairs_hook=collections.OrderedDict)
    except Exception as exc:
        print("Error: %s is not valid JSON (%s) — refusing to touch it" % (SETTINGS, exc),
              file=sys.stderr)
        return 1

    backup = "%s.bak-%d" % (SETTINGS, int(time.time()))
    shutil.copy2(SETTINGS, backup)

    legacy = data.pop("allowedTools", [])
    allow = data.setdefault("permissions", collections.OrderedDict()).setdefault("allow", [])
    merged = list(dict.fromkeys(list(allow) + list(legacy)))
    data["permissions"]["allow"] = merged

    hooks = data.setdefault("hooks", collections.OrderedDict())
    added = []
    for event, command in HOOKS:
        groups = hooks.setdefault(event, [])
        if any(h.get("command") == command for g in groups for h in g.get("hooks", [])):
            continue
        groups.append({"matcher": "*",
                       "hooks": [{"type": "command", "command": command, "timeout": 5}]})
        added.append(event)

    tmp = SETTINGS + ".tmp.%d" % os.getpid()
    try:
        with open(tmp, "w") as fh:
            json.dump(data, fh, indent=2)
            fh.write("\n")
        json.load(open(tmp))            # parse-check before replacing
        os.replace(tmp, SETTINGS)
    except Exception:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise

    print("backup:            %s" % backup)
    print("allowedTools:      %s" % ("removed, %d rules folded in" % len(legacy) if legacy
                                     else "absent (already migrated)"))
    print("permissions.allow: %d rules" % len(merged))
    print("blank-state hooks: %s" % (", ".join(added) if added else "already registered"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
