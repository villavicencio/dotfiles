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
    fleet-check.py             # verify if a snapshot exists, else snapshot

Read-only: it never mutates herdr state. Repairs are printed for you to run.
"""
import json
import os
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
    with open(SNAP, "w") as f:
        json.dump(rows, f, indent=2)
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
    print("\nNow: brew services restart herdr   (from a terminal OUTSIDE herdr)")
    print("Then: fleet-check.py verify")


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
                node = {"type": "pane", "cwd": prev.get("cwd"), "command": cmd}
                req = {"id": "1", "method": "layout.apply",
                       "params": {"tab_id": r["tab"], "focus": True, "root": node}}
                print("    rebuild (omit pane_id so herdr replaces the pane):")
                print(f"      echo '{json.dumps(req)}' | nc -U {SOCK}")
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
    sys.exit(f"unknown command: {cmd} (expected snapshot|verify)")


if __name__ == "__main__":
    sys.exit(main())
