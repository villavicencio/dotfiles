#!/usr/bin/env python3
"""Where a pilot worker's time went, read from its worker.jsonl.

Splits each run into thinking, tool execution and everything else (mostly LM
Studio reading the prompt and Qwen writing replies and tool calls), and shows
the longest single think, the largest context and how the run ended.

The figures come from the transcript itself: each assistant event carries
`thinking_duration_ms`, and tool time runs from the assistant event that
issued a tool call to the user event holding its result. The
`system/thinking_tokens` events are running estimates per step, not amounts
to add up, so they aren't used. Tool calls issued together can run at the
same time, so overlapping tool time is counted once.

A worker that was stopped (or died) has no `result` event, and its transcript
ends at the last event it wrote, often minutes before the end. The end time
and whether it was killed come from `worker.ended_at` and `worker.killed` in
the `run.json` beside the transcript. A tool call still running at the end
counts as tool time; any other time after the last event is shown as "cut
off", a think or reply that never reached the transcript. Without an end time
(no run.json, a runner-error run, or one from before ended_at existed) the
total stops at the last event, and the report says so.

Usage: timing.py <run dir or worker.jsonl> ...
       timing.py ~/runs/log/vil-380-*/
"""

import datetime as dt
import json
import sys
from pathlib import Path


def ts(s):
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))


def span_ms(spans):
    """Total length of the (start, end) spans, counting overlaps once."""
    total, reach = 0.0, None
    for start, end in sorted(spans):
        if reach is not None:
            start = max(start, reach)
        if end > start:
            total += (end - start).total_seconds() * 1000
        reach = end if reach is None else max(reach, end)
    return total


def worker_end(path):
    """When a worker with no result event ended, and how, from run.json.
    Without a recorded end, None and the reason it's missing."""
    try:
        run = json.loads((path.parent / "run.json").read_text())
    except (OSError, ValueError):
        return None, "no run.json"
    if not isinstance(run, dict):
        return None, "run.json isn't an object"
    w = run.get("worker")
    try:
        end = ts(w["ended_at"])
    except (KeyError, TypeError, ValueError):
        return None, f"no worker end time in run.json (status {run.get('status')})"
    if w.get("killed"):
        return end, f"stopped: {w['killed']}"
    return end, f"exited {w.get('exit')} with no result event"


def analyse(path):
    replies = {}        # message id -> thinking ms and context of that reply
    pending = {}        # tool_use id -> when the call was issued
    spans = []          # (issued, answered) for each finished tool call
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
                        spans.append((start, t))
        elif e.get("type") == "result":
            result = e
    cut_ms = 0.0
    if result and result.get("duration_ms"):
        total_ms = result["duration_ms"]
        lines = (result.get("result") or "").strip().splitlines()
        ended = lines[0][:50] if lines else f"{result.get('subtype') or 'result'}, no final text"
    elif first:
        end, how = worker_end(path)
        if end:
            end = max(end, last)
            ended = how
        else:
            end = last
            ended = f"no result event; {how}, so the total stops at the last event"
        total_ms = (end - first).total_seconds() * 1000
        # Calls still running were issued at or before the last event, so they
        # cover the whole tail; without one, the tail is unrecorded.
        spans += [(start, end) for start in pending.values()]
        if not pending:
            cut_ms = (end - last).total_seconds() * 1000
    else:
        total_ms = 0
        ended = "empty transcript"
    think_ms = sum(r["think_ms"] for r in replies.values())
    tool_ms = span_ms(spans)
    return {
        "replies": len(replies),
        "total": total_ms / 60000,
        "think": think_ms / 60000,
        "think_pct": 100 * think_ms / total_ms if total_ms else 0,
        "tools": tool_ms / 60000,
        "cut": cut_ms / 60000,
        "other": (total_ms - think_ms - tool_ms - cut_ms) / 60000,
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
              " tools {tools:.1f}, other {other:.1f}".format(**r)
              + (", cut off {cut:.1f}".format(**r) if r["cut"] else ""))
        print("  longest think {longest:.1f} min, max context {ctx:,} tokens,"
              " ended: {ended}".format(**r))


if __name__ == "__main__":
    main(sys.argv[1:])
