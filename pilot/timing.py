#!/usr/bin/env python3
"""Where a pilot worker's time went, read from its worker.jsonl.

Splits each run into thinking, tool execution and everything else (mostly LM
Studio reading the prompt and Qwen writing replies and tool calls), and shows
the longest single think, the largest context and how the run ended.

The figures come from the transcript itself: each assistant event carries
`thinking_duration_ms`, and tool time runs from the assistant event that
issued a tool call to the user event holding its result. The
`system/thinking_tokens` events are running estimates per step, not amounts
to add up, so they aren't used.

Usage: timing.py <run dir or worker.jsonl> ...
       timing.py ~/runs/log/vil-380-*/
"""

import datetime as dt
import json
import sys
from pathlib import Path


def ts(s):
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))


def analyse(path):
    replies = {}        # message id -> thinking ms and context of that reply
    pending = {}        # tool_use id -> when the call was issued
    tool_ms = 0.0
    first = last = None
    result = None
    for line in open(path):
        try:
            e = json.loads(line)
        except ValueError:
            continue
        t = ts(e["timestamp"]) if e.get("timestamp") else None
        if t:
            first = first or t
            last = t
        if e.get("type") == "assistant":
            m = e["message"]
            u = m.get("usage", {})
            r = replies.setdefault(m.get("id"), {"think_ms": 0, "ctx": 0})
            # One reply arrives as several events; each repeats its thinking time.
            r["think_ms"] = max(r["think_ms"], int(e.get("thinking_duration_ms") or 0))
            r["ctx"] = max(r["ctx"], u.get("input_tokens", 0)
                           + u.get("cache_read_input_tokens", 0)
                           + u.get("cache_creation_input_tokens", 0))
            for b in m.get("content", []):
                if b.get("type") == "tool_use" and t:
                    pending[b["id"]] = t
        elif e.get("type") == "user" and t:
            content = e.get("message", {}).get("content", [])
            for b in content if isinstance(content, list) else []:
                if isinstance(b, dict) and b.get("type") == "tool_result":
                    start = pending.pop(b.get("tool_use_id"), None)
                    if start:
                        tool_ms += (t - start).total_seconds() * 1000
        elif e.get("type") == "result":
            result = e
    if result and result.get("duration_ms"):
        total_ms = result["duration_ms"]
        ended = (result.get("result") or "").strip().splitlines()[0][:50]
    else:
        total_ms = (last - first).total_seconds() * 1000 if first else 0
        ended = "no result event: the worker was stopped"
    think_ms = sum(r["think_ms"] for r in replies.values())
    return {
        "replies": len(replies),
        "total": total_ms / 60000,
        "think": think_ms / 60000,
        "think_pct": 100 * think_ms / total_ms if total_ms else 0,
        "tools": tool_ms / 60000,
        "other": (total_ms - think_ms - tool_ms) / 60000,
        "longest": max((r["think_ms"] for r in replies.values()), default=0) / 60000,
        "ctx": max((r["ctx"] for r in replies.values()), default=0),
        "ended": ended,
    }


def main(args):
    if not args:
        sys.exit(__doc__.strip())
    for a in args:
        p = Path(a).expanduser()
        if p.is_dir():
            p = p / "worker.jsonl"
        if not p.exists():
            print(f"{a}: no worker.jsonl")
            continue
        r = analyse(p)
        print(p.parent.name)
        print("  {total:.1f} min, {replies} replies: thinking {think:.1f} min ({think_pct:.0f}%),"
              " tools {tools:.1f}, other {other:.1f}".format(**r))
        print("  longest think {longest:.1f} min, max context {ctx:,} tokens,"
              " ended: {ended}".format(**r))


if __name__ == "__main__":
    main(sys.argv[1:])
