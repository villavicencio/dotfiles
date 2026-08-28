#!/usr/bin/env python3
"""fleet-check — snapshot the herdr fleet before a server restart, verify it after.

A herdr server restart kills every pane process. Most things come back on their
own, but two do not, and both fail *quietly*:

  1. The #2966 restore boot-race drops a declarative pane's `command` from the
     layout. The pane looks fine — someone starts claude in it by hand and it is
     detected normally — but the next restart returns an empty shell. The tell is
     a `layout.export` pane node with no `command` key.
  2. Agent names do not survive pane recreation, and the jump keys target names,
     so a rebuilt pane silently breaks `prefix+<key>`.

Usage:
    fleet-check.py snapshot    # before `brew services restart herdr`
    fleet-check.py verify      # after reattaching
    fleet-check.py repair      # rebuild lost panes that have no live agent,
                               #   relaunching each into its conversation
    fleet-check.py repair --no-resume   # ...into a blank session instead
    fleet-check.py             # verify if a snapshot exists, else snapshot

`snapshot` and `verify` are read-only — `verify` prints the repairs rather than
running them. `repair` is the one subcommand that mutates: it calls `layout.apply`,
which kills and replaces the pane it rebuilds.
"""
import json
import os
import re
import socket
import sys

SOCK = os.path.expanduser("~/.config/herdr/herdr.sock")
SNAP = os.path.expanduser("~/.config/herdr/fleet-snapshot.json")


def call(method, params=None):
    """One NDJSON request/response over the herdr socket.

    Every request needs a `params` key even when empty — omitting it fails with
    `missing field params`.
    """
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(SOCK)
    except (FileNotFoundError, ConnectionRefusedError) as e:
        sys.exit(f"herdr socket unavailable at {SOCK} ({e}). Is the server running?")
    s.sendall((json.dumps({"id": "1", "method": method, "params": params or {}}) + "\n").encode())
    buf = b""
    while not buf.endswith(b"\n"):
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
    s.close()
    d = json.loads(buf.decode())
    if "error" in d:
        sys.exit(f"{method} failed: {d['error']}")
    return d.get("result", {})


def tabs():
    """Every tab id in the session. layout.export silently ignores workspace_id
    and returns the *focused* workspace, so panes must be addressed by tab_id."""
    out = []
    for w in call("workspace.list").get("workspaces", []):
        wid, label = w["workspace_id"], w.get("label", wid_fallback(w))
        found = []
        try:
            for t in call("tab.list", {"workspace_id": wid}).get("tabs", []):
                found.append(t["tab_id"])
        except SystemExit:
            pass
        if not found and w.get("active_tab_id"):
            found = [w["active_tab_id"]]
        for t in found:
            out.append((wid, label, t))
    return out


def wid_fallback(w):
    return w.get("workspace_id", "?")


def collect():
    """Live fleet state: one row per pane, plus the agent overlay."""
    agents = {a["pane_id"]: a for a in call("agent.list").get("agents", [])}
    rows = []
    for wid, label, tid in tabs():
        root = call("layout.export", {"tab_id": tid}).get("layout", {}).get("root", {})
        for pane in walk(root):
            pid = pane.get("pane_id")
            a = agents.get(pid, {})
            rows.append({
                "workspace": wid,
                "label": label,
                "tab": tid,
                "pane": pid,
                "has_command": bool(pane.get("command")),
                "command": pane.get("command"),
                "cwd": pane.get("cwd"),
                "name": a.get("name"),
                "agent": a.get("agent"),
                "status": a.get("agent_status"),
                "resumable": bool(a.get("agent_session")),
            })
    return rows


def walk(node):
    """Layout trees nest splits; yield every pane leaf."""
    if not isinstance(node, dict):
        return
    if node.get("type") == "pane":
        yield node
        return
    for child in node.get("children", []) or []:
        yield from walk(child)


def key(r):
    """Identity that survives a rebuild. See the comment in do_verify()."""
    return f"{r.get('label')}\x00{r.get('cwd') or r.get('tab')}"


def do_snapshot(rows):
    # Merge, never clobber. A pane whose command was already lost reads as
    # command-less in live state, so a plain overwrite would DESTROY the only
    # record of how to rebuild it — losing recovery data every time you snapshot
    # after a bad restart, which is exactly when you need it most.
    carried = 0
    if os.path.exists(SNAP):
        try:
            prev = {key(r): r for r in json.load(open(SNAP))}
        except (json.JSONDecodeError, OSError):
            prev = {}
        for r in rows:
            if not r.get("command"):
                old_cmd = prev.get(key(r), {}).get("command")
                if old_cmd:
                    r["command"] = old_cmd
                    r["command_carried"] = True
                    carried += 1
    with open(SNAP, "w") as f:
        json.dump(rows, f, indent=2)
    if carried:
        print(f"  (carried {carried} command(s) forward from the previous snapshot)")
    named = [r for r in rows if r["name"]]
    degraded = [r for r in rows if not r["has_command"]]
    print(f"snapshot written: {SNAP}")
    print(f"  {len(rows)} panes, {len(named)} named, "
          f"{sum(1 for r in rows if r['resumable'])} resumable")
    if degraded:
        print(f"\n  ⚠ {len(degraded)} pane(s) are ALREADY degraded (no command in the layout).")
        print("    Rebuild these before restarting, or they come back as bare shells:")
        for r in degraded:
            print(f"      {r['label']}  tab={r['tab']}  pane={r['pane']}")
    print("\nNext — all of this from a terminal OUTSIDE herdr:")
    print("  1. UPGRADING? first:  brew bundle install --file="
          "~/Projects/Personal/dotfiles/brew/Brewfile")
    print("     (installs the new binary; does NOT restart, panes keep running)")
    print("  2. brew services restart herdr")
    print("     (RESTART ONLY — it never upgrades. Kills every pane, including")
    print("      the shell you type it into if that shell is a herdr pane.)")
    print("  3. python3 ~/Projects/Personal/dotfiles/herdr/fleet-check.py verify")


# The two forms a local agent launch can take, from one source of truth so the
# resume and blank directions can never drift apart. The fleet pane template
# carries the resuming form since 2026-08-27; a snapshot taken before that flip
# records the bare one, and restoring it verbatim would launch the agent FRESH —
# the pane looks blank while the previous conversation sits unloaded on disk.
# `|| <bare>` is load-bearing: `--continue` exits 1 when the directory has no
# prior session, and without the fallback the pane would land at a shell.
AGENT_LAUNCHERS = ["claude", "hermes chat"]


def _bare(agent):
    return f"{agent};"


def _resuming(agent):
    return f"{agent} --continue || {agent};"


# Each table anchors on the form it converts FROM, so applying either to a command
# already in the target form is a no-op — the rewrites are idempotent, and a
# remote shim command matches neither.
RESUME_REWRITES = [(re.compile("^" + re.escape(_bare(a))), _resuming(a))
                   for a in AGENT_LAUNCHERS]
BLANK_REWRITES = [(re.compile("^" + re.escape(_resuming(a))), _bare(a))
                  for a in AGENT_LAUNCHERS]


def _rewrite(cmd, table):
    """Swap the launcher in a pane command's final shell string.

    Remote shim commands are deliberately untouched by both tables: their agent
    lives in tmux on the VPS and was never killed, so the shim reattaches to a
    live session and there is nothing local to resume or blank.
    """
    if not cmd or len(cmd) < 2:
        return cmd, False
    shell = cmd[-1]
    if not isinstance(shell, str):
        return cmd, False
    for pat, repl in table:
        if pat.match(shell):
            # A lambda replacement so a backslash in `repl` is never read as a
            # backreference.
            return cmd[:-1] + [pat.sub(lambda m, r=repl: r, shell, count=1)], True
    return cmd, False


def resume_variant(cmd):
    """Upgrade a bare LOCAL agent launch to resume. Returns (command, changed?)."""
    return _rewrite(cmd, RESUME_REWRITES)


def blank_variant(cmd):
    """Strip the resume wrapper from a LOCAL agent launch, for `--no-resume`.

    Needed because the pane template now records the resuming form: without this
    the opt-out would restore that form verbatim and silently resume anyway.
    """
    return _rewrite(cmd, BLANK_REWRITES)


def do_repair(rows, force=False, resume=True):
    """Rebuild panes whose command was lost — but never one with a live agent.

    After a restart the two populations look identical in `layout.export` (both
    lost their command) and could not be more different in practice: a pane whose
    agent resumed is holding a live conversation, and `layout.apply` would destroy
    it to fix metadata that only matters at the *next* restart. A bare shell has
    nothing to lose. Repair the second group; leave the first for a boundary.
    """
    if not os.path.exists(SNAP):
        sys.exit(f"no snapshot at {SNAP} — nothing to repair from")
    by_key = {key(r): r for r in json.load(open(SNAP))}

    todo, holding, unknown = [], [], []
    for r in rows:
        if r["has_command"]:
            continue
        cmd = by_key.get(key(r), {}).get("command")
        if not cmd:
            unknown.append(r)
        elif r["agent"] and not force:
            holding.append(r)
        else:
            todo.append((r, cmd))

    if holding:
        print(f"HOLDING ({len(holding)}) — live agent, would lose the conversation. "
              "Rebuild at a boundary, or re-run with --force:")
        for r in holding:
            print(f"  {r['label']:16} pane={r['pane']} status={r['status']}")
        print()
    if unknown:
        print(f"NO RECORD ({len(unknown)}) — not in the snapshot, rebuild by hand:")
        for r in unknown:
            print(f"  {r['label']:16} tab={r['tab']}")
        print()
    if not todo:
        print("nothing to repair")
        return 0

    print(f"REBUILDING {len(todo)} pane(s) with no live agent:")
    for r, cmd in todo:
        prev = by_key[key(r)]
        if not resume:
            cmd, stripped = blank_variant(cmd)
            tag = ("  [--no-resume: resume wrapper stripped, blank session]" if stripped
                   else "  [--no-resume: blank session]")
        else:
            cmd, rewritten = resume_variant(cmd)
            shell = cmd[-1] if cmd and isinstance(cmd[-1], str) else ""
            if rewritten:
                tag = "  [resume: rewritten from a pre-2026-08-27 snapshot]"
            elif "--continue" in shell:
                tag = "  [resume: already in the recorded command]"
            else:
                tag = "  [no local agent to resume]"
        node = {"type": "pane", "cwd": prev.get("cwd"), "command": cmd}
        res = call("layout.apply", {"tab_id": r["tab"], "focus": False, "root": node})
        new = res.get("layout", {}).get("root", {}).get("pane_id")
        print(f"  ✓ {r['label']:16} {r['pane']} -> {new}{tag}")

    print("\nRe-run `fleet-check.py verify` once they settle, then reapply names.")
    return 0


def do_verify(rows):
    if not os.path.exists(SNAP):
        sys.exit(f"no snapshot at {SNAP} — run `fleet-check.py snapshot` first")
    snap = json.load(open(SNAP))
    before = {r["pane"]: r for r in snap}
    # Key by (workspace label, cwd). None of the ids are stable: pane ids change
    # when a pane is rebuilt, and `layout.apply` MINTS A NEW TAB ID rather than
    # reusing the one you addressed (verified 2026-08-26: w9:t3 -> w9:t9). A
    # workspace label alone collides — sites holds four panes — but the pane's
    # working directory is the project it belongs to and does not move.
    by_key = {key(r): r for r in snap}

    degraded = [r for r in rows if not r["has_command"]]
    lost_name = [r for r in rows
                 if not r["name"] and by_key.get(key(r), {}).get("name")]
    undetected = [r for r in rows if r["has_command"] and not r["agent"]]

    ok = True
    print(f"live: {len(rows)} panes  (snapshot had {len(before)})\n")

    if degraded:
        ok = False
        print(f"⚠ DEGRADED — command dropped from the layout ({len(degraded)}):")
        for r in degraded:
            prev = by_key.get(key(r), {})
            cmd = prev.get("command")
            print(f"\n  {r['label']}  tab={r['tab']}")
            if cmd:
                # Print what `repair` would actually run, not the raw snapshot. A
                # snapshot older than the 2026-08-27 template flip records the bare
                # form, so pasting it verbatim rebuilds the pane into a BLANK
                # session while `repair` would have resumed it — the two repair
                # paths must not disagree.
                cmd, upgraded = resume_variant(cmd)
                node = {"type": "pane", "cwd": prev.get("cwd"), "command": cmd}
                req = {"id": "1", "method": "layout.apply",
                       "params": {"tab_id": r["tab"], "focus": True, "root": node}}
                print("    rebuild (omit pane_id so herdr replaces the pane):")
                print(f"      echo '{json.dumps(req)}' | nc -U {SOCK}")
                if upgraded:
                    print("      (resume wrapper added — this snapshot predates the "
                          "template flip; use `repair --no-resume` for a blank pane)")
            else:
                print("    no command recorded in the snapshot — rebuild by hand")
    else:
        print("✓ no degraded panes — every pane kept its command")

    if lost_name:
        ok = False
        print(f"\n⚠ NAMES LOST — jump keys target these ({len(lost_name)}):")
        for r in lost_name:
            want = by_key[key(r)]["name"]
            print(f"      /opt/homebrew/bin/herdr agent rename {r['pane']} {want}")
    else:
        print("✓ all agent names intact")

    if undetected:
        print(f"\n· undetected ({len(undetected)}) — check the foreground process; "
              "a fallback zsh means a clean detach, not a detection bug:")
        for r in undetected:
            print(f"      {r['label']}  pane={r['pane']}  status={r['status']}")

    nonres = [r for r in rows if r["agent"] and not r["resumable"]]
    if nonres:
        print(f"\n· no session ref ({len(nonres)}) — these restore cold rather than "
              "resuming. Remote ssh panes are expected here; their agents live on the VPS:")
        for r in nonres:
            print(f"      {r['label']:14} agent={r['agent']}")

    print("\n" + ("✓ fleet healthy" if ok else "⚠ action needed — commands above"))
    return 0 if ok else 1


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ("verify" if os.path.exists(SNAP) else "snapshot")
    rows = collect()
    if cmd == "snapshot":
        do_snapshot(rows)
        return 0
    if cmd == "verify":
        return do_verify(rows)
    if cmd == "repair":
        # --resume is accepted as a no-op so older muscle memory still works.
        return do_repair(rows, force="--force" in sys.argv,
                         resume="--no-resume" not in sys.argv)
    sys.exit(f"unknown command: {cmd} (expected snapshot|verify|repair)")


if __name__ == "__main__":
    sys.exit(main())
