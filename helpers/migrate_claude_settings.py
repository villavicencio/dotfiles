#!/usr/bin/env python3
"""Bring an existing ~/.claude/settings.json in line with changes the copy-seed can't reach.

The tracked claude/settings.json is copied in only when the live file is absent, so a
change to it never reaches a machine that already has one. Two fixes, both idempotent —
safe to re-run, and a no-op once applied:

1. Undo a resurrected legacy top-level `allowedTools` key. When both it and
   `permissions.allow` exist, the LEGACY KEY WINS and permissions.allow is
   silently inert — rules sit there looking active while nothing consults them.
   PR #127 consolidated onto permissions.allow; this machine's live file had
   regrown allowedTools with 18 rules against a permissions.allow of 1.
   Folds allowedTools into permissions.allow (dedup, order-preserving) and
   deletes the legacy key.

2. Remove every hook whose command mentions herdr. herdr was retired on 2026-10-22
   (VIL-422): its blank-state hook links into this repo, so once a machine pulls the
   retirement the link dangles and every SessionStart/UserPromptSubmit prints a hook
   error. Run `herdr integration uninstall claude` first where herdr is still
   installed; this catches what that leaves, including our own blank-state entries.
   (Until VIL-422 this step registered the blank-state hook instead.)

3. Desk Macs and Windows only, where the seed runs: add every top-level key of the tracked
   file that the live file lacks (the machine-local
   keys below and the "//" header excepted), with the tracked value. That's what a fresh
   seed would have given this machine: `autoCompactWindow` (VIL-402), say. A key already
   there is the machine's choice and is left alone. A tracked key you dropped on purpose
   is deleted from the tracked file, not re-added here. `--capture` refuses while such a
   gap exists, and points here.

Run it on any machine whose settings.json predates 2026-08-25, on any Mac that had
herdr, and after a change to a tracked key this script carries. Writes a timestamped backup first and parse-checks before replacing.

NOTE: Claude Code's auto-mode classifier blocks agents from writing this file
(by design — it stops an agent widening its own permissions), so this is a
human-run script. Invoke it yourself:

    python3 helpers/migrate_claude_settings.py

Under Git Bash on Windows `python3` is usually the Microsoft Store placeholder,
so call it as `python`, or as `uv run --no-project python helpers/migrate_claude_settings.py`
on a PC that has no Python of its own (one set up only by install.ps1).
"""
import collections
import copy
import json
import os
import shutil
import sys
import time

SETTINGS = os.path.expanduser("~/.claude/settings.json")
# Keep in step with STRIP_KEYS in helpers/install_claude_settings.sh: never tracked.
MACHINE_LOCAL = {"effortLevel", "modelSettings", "autoMode", "mcpServers", "allowedTools"}
# The tracked baseline this repo seeds: Windows has its own sibling.
_REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_ON_WINDOWS = os.name == "nt" or sys.platform in ("cygwin", "msys")
TRACKED = os.path.join(_REPO, "windows" if _ON_WINDOWS else "claude",
                       "claude-settings.json" if _ON_WINDOWS else "settings.json")
# The seed runs only on desk Macs (darwin.yaml) and Windows (install.ps1). Linux and hal's
# server profile never get one, so the Mac baseline's tmux hooks and iTerm channel don't belong
# there (MergeWren a1375c7#1). The server profile is the install that links
# ~/.config/zsh/.zprofile to zsh/zprofile.server.
_ZPROFILE = os.path.realpath(os.path.expanduser("~/.config/zsh/.zprofile"))
SEEDED = _ON_WINDOWS or (sys.platform == "darwin" and not _ZPROFILE.endswith("zsh/zprofile.server"))


def main():
    if os.environ.get("DOTFILES_DRY_RUN", "0") == "1":
        print("[dry-run] would repair %s (allowedTools fold, herdr hook removal, missing tracked keys)" % SETTINGS)
        return 0
    if not os.path.exists(SETTINGS):
        print("No settings at %s — nothing to migrate." % SETTINGS)
        return 0

    try:
        data = json.load(open(SETTINGS, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
    except Exception as exc:
        print("Error: %s is not valid JSON (%s) — refusing to touch it" % (SETTINGS, exc),
              file=sys.stderr)
        return 1

    # Decide before touching anything: an already-migrated file gets no backup
    # and no rewrite, so re-running really is a no-op.
    def is_herdr(h):
        return "herdr" in str(h.get("command", ""))
    hooks = data.get("hooks") or {}
    herdr = [(e, h.get("command")) for e, groups in hooks.items() if isinstance(groups, list)
             for g in groups if isinstance(g, dict) for h in g.get("hooks", []) if is_herdr(h)]
    try:
        tracked = json.load(open(TRACKED, encoding="utf-8"), object_pairs_hook=collections.OrderedDict)
    except Exception as exc:
        print("Error: cannot read the tracked settings at %s (%s) — refusing to migrate"
              % (TRACKED, exc), file=sys.stderr)
        return 1
    missing = ([k for k in tracked if k != "//" and k not in MACHINE_LOCAL and k not in data]
               if SEEDED else [])
    if "allowedTools" not in data and not herdr and not missing:
        print("Nothing to migrate: no allowedTools key, no herdr hooks, no missing tracked keys.")
        return 0

    backup = "%s.bak-%d" % (SETTINGS, int(time.time()))
    shutil.copy2(SETTINGS, backup)

    # Missing tracked keys first, so the fold below lands in what a fresh seed would have
    # given this machine: a `permissions` block it lacked arrives whole (defaultMode and all),
    # and the legacy rules then merge into its `allow` (MergeWren 8d3b94c#1, 2aa9ec9#1).
    for k in missing:
        data[k] = copy.deepcopy(tracked[k])

    legacy = data.pop("allowedTools", [])
    allow = data.setdefault("permissions", collections.OrderedDict()).setdefault("allow", [])
    merged = list(dict.fromkeys(list(allow) + list(legacy)))
    data["permissions"]["allow"] = merged

    if herdr:
        for event in list(hooks):
            groups = hooks[event]
            if not isinstance(groups, list):
                continue
            kept = []
            for g in groups:
                if isinstance(g, dict) and isinstance(g.get("hooks"), list):
                    g["hooks"] = [h for h in g["hooks"] if not is_herdr(h)]
                    if not g["hooks"]:
                        continue
                kept.append(g)
            if kept:
                hooks[event] = kept
            else:
                del hooks[event]

    tmp = SETTINGS + ".tmp.%d" % os.getpid()
    try:
        with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(data, fh, indent=2)
            fh.write("\n")
        json.load(open(tmp, encoding="utf-8"))  # parse-check before replacing
        os.replace(tmp, SETTINGS)
    except Exception:
        if os.path.exists(tmp):
            os.remove(tmp)
        raise

    print("backup:            %s" % backup)
    print("allowedTools:      %s" % ("removed, %d rules folded in" % len(legacy) if legacy
                                     else "absent (already migrated)"))
    print("permissions.allow: %d rules" % len(merged))
    print("tracked keys added: %s" % (", ".join(missing) if missing
                                      else "none missing" if SEEDED
                                      else "skipped (no seeded baseline on Linux or the server profile)"))
    print("herdr hooks:       %s" % ("removed: " + ", ".join("%s %s" % h for h in herdr) if herdr
                                     else "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
