#!/usr/bin/env python3
"""hal Local Coding Pilot runner (VIL-396).

Runs on hal as `david`, from a LaunchDaemon in the overnight window. For each
queued ticket it:

  1. checks the gates (kill switch, lock, free memory, LM Studio);
  2. makes a fresh worktree of the target repo on a `pilot/*` branch;
  3. has Opus (david's claude.ai login) write the brief and acceptance checks;
  4. has the local Qwen worker (`claude -p --bare` against LM Studio) do the work;
  5. runs the acceptance checks itself;
  6. commits, pushes the `pilot/*` branch and opens a PR, marked failed
     when the checks fail, so failures get counted.

Nothing here merges, pushes a default branch, or touches `~/.ssh` or david's
`gh` login: GitHub access is the fine-grained token in GH_TOKEN, set only in
the child processes that need it.

Usage: runner.py [--once] [--dry-run] [--ticket FILE]
"""

import argparse
import datetime as dt
import fcntl
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

HOME = Path.home()
RUNS = Path(os.environ.get("PILOT_RUNS", HOME / "runs"))
SECRETS = HOME / ".config" / "hal-pilot"
HERE = Path(__file__).resolve().parent

OWNER = "villavicencio"
REPOS = {"dotfiles", "bryancola.com", "browse-gateway", "mergewren"}

LMSTUDIO_URL = "http://127.0.0.1:1234"
WORKER_MODEL = "qwen3.8-27b"
PLANNER_MODEL = "opus"

MIN_FREE_PCT = 20          # skip the night below this (VIL-395 decision)
ABORT_FREE_PCT = 10        # kill a running worker below this
MAX_TICKETS_PER_NIGHT = 3
STOP_STARTING_AT = dt.time(6, 0)   # local (PT) — don't start a ticket after this
PLANNER_TIMEOUT_S = 20 * 60
WORKER_TIMEOUT_S = 60 * 60
CHECK_TIMEOUT_S = 15 * 60
SYNC_TIMEOUT_S = 10 * 60
PLANNER_BUDGET_USD = "10"

# Bash commands the worker may always run, on top of the brief's checks.
WORKER_READONLY_BASH = [
    "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)",
    "Bash(git show:*)", "Bash(ls:*)", "Bash(rg:*)", "Bash(grep:*)",
]

PLAN_SCHEMA = {
    "type": "object",
    "properties": {
        "proceed": {"type": "boolean"},
        "reason": {"type": "string"},
        "brief": {"type": "string"},
        "checks": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "cmd": {"type": "string"},
                },
                "required": ["name", "cmd"],
            },
        },
        "pr_title": {"type": "string"},
    },
    "required": ["proceed", "reason", "brief", "checks", "pr_title"],
}


def log(msg):
    print(f"{dt.datetime.now().isoformat(timespec='seconds')} {msg}", flush=True)


def read_secret(name):
    return (SECRETS / name).read_text().strip()


# ---------------------------------------------------------------- gates

def disabled():
    return (RUNS / "DISABLED").exists()


def free_memory_pct():
    out = subprocess.run(["/usr/bin/memory_pressure"], capture_output=True,
                         text=True, timeout=60).stdout
    m = re.search(r"System-wide memory free percentage:\s*(\d+)%", out)
    if not m:
        raise RuntimeError("memory_pressure output had no free percentage")
    return int(m.group(1))


def lmstudio_has_worker_model():
    req = urllib.request.Request(
        f"{LMSTUDIO_URL}/v1/models",
        headers={"Authorization": f"Bearer {read_secret('lmstudio-token')}"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            ids = [m.get("id") for m in json.load(r).get("data", [])]
    except (urllib.error.URLError, OSError, ValueError) as e:
        log(f"LM Studio unreachable: {e}")
        return False
    return WORKER_MODEL in ids


# ---------------------------------------------------------------- queue

def parse_ticket(path):
    """A queued ticket is markdown with a small frontmatter:

        ---
        id: VIL-123
        repo: dotfiles
        title: Fix the thing
        ---
        <ticket body, as approved by David>
    """
    text = path.read_text()
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.S)
    if not m:
        raise ValueError(f"{path.name}: no frontmatter")
    meta = {}
    for line in m.group(1).splitlines():
        k, _, v = line.partition(":")
        meta[k.strip()] = v.strip().strip('"')
    for k in ("id", "repo", "title"):
        if not meta.get(k):
            raise ValueError(f"{path.name}: missing {k}")
    if meta["repo"] not in REPOS:
        raise ValueError(f"{path.name}: repo {meta['repo']!r} is not a pilot repo")
    if not re.fullmatch(r"[A-Z]+-\d+", meta["id"]):
        raise ValueError(f"{path.name}: bad id {meta['id']!r}")
    meta["body"] = m.group(2).strip()
    meta["path"] = path
    return meta


def next_ticket():
    queue = RUNS / "queue"
    for p in sorted(queue.glob("*.md"), key=lambda p: p.stat().st_mtime):
        try:
            return parse_ticket(p)
        except ValueError as e:
            log(f"skipping bad ticket: {e}")
            shelve(p, "rejected")
    return None


def free_name(target, tag):
    """target, or the first `<stem>.<tag>-<n><suffix>` beside it that doesn't exist yet: a
    timestamp alone repeats within a second (MergeWren fae1693#2)."""
    base, n = target, 1
    while target.exists():
        target = base.with_name(f"{base.stem}.{tag}-{n}{base.suffix}")
        n += 1
    return target


def shelve_back(path):
    # A new ticket may have arrived under the same name; keep both.
    return Path(shutil.move(str(path), free_name(RUNS / "queue" / path.name, "requeued")))


def shelve(path, where):
    dest = RUNS / "queue" / where
    dest.mkdir(parents=True, exist_ok=True)
    # The same name may have been shelved here before; keep both.
    return Path(shutil.move(str(path), free_name(dest / path.name, "again")))


# ---------------------------------------------------------------- git

def git_env(gh_token):
    """Child env for git/gh: the pilot token only, never david's login."""
    env = dict(os.environ)
    env["GH_TOKEN"] = gh_token
    env["GIT_TERMINAL_PROMPT"] = "0"
    env["GIT_ASKPASS"] = "/usr/bin/false"
    env["SSH_ASKPASS"] = "/usr/bin/false"
    return env


# Resets david's credential helpers, then answers with GH_TOKEN from the env.
CRED_ARGS = [
    "-c", "credential.helper=",
    "-c", "credential.helper=!f() { test \"$1\" = get || exit 0; "
          "echo username=x-access-token; echo \"password=$GH_TOKEN\"; }; f",
]


def git(args, cwd, env, check=True):
    r = subprocess.run(["git", *CRED_ARGS, *args], cwd=cwd, env=env,
                       capture_output=True, text=True, timeout=600)
    if check and r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)}: {r.stderr.strip()}")
    return r.stdout.strip()


def prepare_worktree(repo, branch, wt, env):
    clone = RUNS / "repos" / repo
    url = f"https://github.com/{OWNER}/{repo}.git"
    if not clone.exists():
        clone.parent.mkdir(parents=True, exist_ok=True)
        git(["clone", "--no-checkout", url, str(clone)], RUNS, env)
    hooks = clone / ".git" / "hooks"
    shutil.copyfile(HERE / "pre-push", hooks / "pre-push")
    (hooks / "pre-push").chmod(0o755)
    # Pin hooksPath so a global core.hooksPath can't bypass the pre-push guard.
    git(["config", "core.hooksPath", str(hooks)], clone, env)
    git(["remote", "set-url", "origin", url], clone, env)
    git(["fetch", "--prune", "origin"], clone, env)
    # fetch doesn't move origin/HEAD when the default branch changes; ask the remote.
    git(["remote", "set-head", "origin", "--auto"], clone, env)
    git(["worktree", "prune"], clone, env)
    default = git(["symbolic-ref", "--short", "refs/remotes/origin/HEAD"], clone, env)
    git(["worktree", "add", "-b", branch, str(wt), default], clone, env)
    return default.split("/", 1)[1]


def sync_env(wt, rundir):
    """Fill david's uv cache from the worktree's lockfile, online, before the worker starts.
    Tickets have the worker and the checks run `uv run --offline` (the runner doesn't enforce it),
    so a dependency the repo added since the last fill failed every check (VIL-528). Returns
    None when there's no uv.lock or the sync worked, else why; the output is in sync.log."""
    if not (wt / "uv.lock").exists():
        return None
    cmd = ["uv", "sync", "--locked"]
    try:
        rc, out, err, killed = run_limited(cmd, wt, dict(os.environ), SYNC_TIMEOUT_S)
    except OSError as e:   # uv missing or not executable: still env-failed, not runner-error
        rc, out, err, killed = None, "", str(e), "could not start"
    (rundir / "sync.log").write_text(f"$ {' '.join(cmd)}\nexit {rc} {killed or ''}\n{out}{err}")
    if rc == 0 and not killed:
        return None
    return f"`{' '.join(cmd)}` {killed or f'exit {rc}'}: {(out + err).strip()[-1500:]}"


# ---------------------------------------------------------------- processes

CHILD_PGIDS = set()   # process groups started by run_limited and still running


def stop_groups(pgids, grace=10):
    """SIGTERM each group, wait up to `grace` seconds, then SIGKILL what's left."""
    for pgid in pgids:
        try:
            os.killpg(pgid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + grace
    alive = set(pgids)
    while alive and time.monotonic() < deadline:
        for pgid in list(alive):
            try:
                os.killpg(pgid, 0)
            except ProcessLookupError:
                alive.discard(pgid)
        time.sleep(0.5)
    for pgid in alive:
        try:
            os.killpg(pgid, signal.SIGKILL)
        except ProcessLookupError:
            pass


def on_sigterm(*_):
    # Stop the children before unwinding reaches worktree cleanup.
    stop_groups(list(CHILD_PGIDS))
    sys.exit(143)


def run_limited(cmd, cwd, env, timeout, stdin_text=None, watch_memory=False,
                stdout_path=None):
    """Run cmd in its own process group; kill the group on timeout, on the
    kill switch, or (watch_memory) when free memory falls below ABORT_FREE_PCT.
    With stdout_path, stdout goes straight to that file as it is written, so a
    killed process still leaves its output; the returned stdout is then ""."""
    sink = open(stdout_path, "w") if stdout_path else subprocess.PIPE
    try:
        p = subprocess.Popen(cmd, cwd=cwd, env=env, text=True,
                             stdin=subprocess.PIPE, stdout=sink,
                             stderr=subprocess.PIPE, start_new_session=True)
    finally:
        if stdout_path:
            sink.close()
    CHILD_PGIDS.add(p.pid)
    reason = []

    def watchdog():
        deadline = time.monotonic() + timeout
        while p.poll() is None:
            why = None
            if time.monotonic() > deadline:
                why = f"timeout after {timeout}s"
            elif disabled():
                why = "kill switch"
            elif watch_memory:
                try:
                    pct = free_memory_pct()
                    if pct < ABORT_FREE_PCT:
                        why = f"free memory fell to {pct}%"
                except Exception:
                    pass
            if why:
                reason.append(why)
                try:
                    os.killpg(p.pid, signal.SIGTERM)
                    time.sleep(10)
                    os.killpg(p.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                return
            time.sleep(30)

    t = threading.Thread(target=watchdog, daemon=True)
    t.start()
    try:
        out, err = p.communicate(stdin_text)
    finally:
        CHILD_PGIDS.discard(p.pid)
    t.join(timeout=1)
    return p.returncode, out or "", err, (reason[0] if reason else None)


def parse_stream(lines):
    """Summarize a `--output-format stream-json` transcript. The final `result`
    event is only there when claude exits on its own; for a killed worker,
    turns, tokens and the last reply come from the assistant messages."""
    result, msgs, last_text = None, {}, ""
    for line in lines:
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if ev.get("type") == "result":
            result = ev
        elif ev.get("type") == "assistant":
            m = ev.get("message") or {}
            msgs[m.get("id")] = m.get("usage") or {}   # last copy per message wins
            text = "".join(b.get("text", "") for b in m.get("content") or []
                           if b.get("type") == "text")
            last_text = text or last_text
    if result:
        return result
    usage = {}
    for u in msgs.values():
        for k in ("input_tokens", "cache_read_input_tokens",
                  "cache_creation_input_tokens", "output_tokens"):
            usage[k] = usage.get(k, 0) + (u.get(k) or 0)
    return {"is_error": True, "num_turns": len(msgs), "usage": usage,
            "result": last_text}


def parse_claude_json(out):
    try:
        return json.loads(out)
    except ValueError:
        return {"is_error": True, "result": out[-4000:]}


# ---------------------------------------------------------------- stages

def plan(ticket, wt, rundir):
    prompt = (HERE / "plan-prompt.md").read_text().format(
        id=ticket["id"], repo=ticket["repo"], title=ticket["title"],
        body=ticket["body"], readonly=", ".join(WORKER_READONLY_BASH))
    env = dict(os.environ)
    for k in ("ANTHROPIC_BASE_URL", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY"):
        env.pop(k, None)
    cmd = ["claude", "-p", "--model", PLANNER_MODEL,
           "--tools", "Read,Grep,Glob", "--permission-mode", "dontAsk",
           "--strict-mcp-config", "--no-session-persistence",
           "--max-budget-usd", PLANNER_BUDGET_USD,
           "--output-format", "json", "--json-schema", json.dumps(PLAN_SCHEMA)]
    rc, out, err, killed = run_limited(cmd, wt, env, PLANNER_TIMEOUT_S, prompt)
    (rundir / "planner.json").write_text(out)
    (rundir / "planner.stderr").write_text(err)
    res = parse_claude_json(out)
    if killed or rc != 0 or res.get("is_error"):
        raise RuntimeError(f"planner failed ({killed or f'exit {rc}'})")
    plan_obj = res.get("structured_output")
    if plan_obj is None:
        plan_obj = json.loads(res.get("result", ""))
    plan_obj["_cost_usd"] = res.get("total_cost_usd")
    plan_obj["_duration_s"] = round(res.get("duration_ms", 0) / 1000)
    return plan_obj


def bash_rules(checks):
    """The worker's Bash rules, appended to the brief. A rule matches only the
    exact command, so a check with `| head` or `2>&1` added is denied; on
    2026-10-21 a worker spent part of its hour on 14 such denials."""
    exact = "\n".join(f"- `{c['cmd']}`" for c in checks) or "- (none)"
    prefixes = ", ".join(f"`{r[5:-3]}`" for r in WORKER_READONLY_BASH)
    return (
        "\n\n## Your Bash permissions\n\n"
        "Bash runs only these commands, exactly as written (no added pipes, "
        "redirects, `2>&1`, `head`, `cd` or `&&`):\n"
        f"{exact}\n\n"
        f"Plus read-only commands starting with: {prefixes}. Anything else is "
        "denied, so don't probe for other commands. Use Read instead of `cat`, "
        "`head` or `sed`, and Edit to change files.\n")


def work(brief, checks, wt, rundir):
    env = dict(os.environ)
    env.pop("ANTHROPIC_API_KEY", None)
    env.update({
        "ANTHROPIC_BASE_URL": LMSTUDIO_URL,
        "ANTHROPIC_AUTH_TOKEN": read_secret("lmstudio-token"),
        "ANTHROPIC_MODEL": WORKER_MODEL,
        "ANTHROPIC_DEFAULT_OPUS_MODEL": WORKER_MODEL,
        "ANTHROPIC_DEFAULT_SONNET_MODEL": WORKER_MODEL,
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": WORKER_MODEL,
        # No auto-compaction: on 2026-10-21 the worker started compacting at about
        # 30k tokens of context and produced nothing for 10 minutes, which is
        # likely how every mergewren run on 2026-10-18 used up its hour. LM Studio
        # loads the model with 234k of context, so the cap is raised instead; a
        # worker that still runs out fails fast rather than hanging. At 128k,
        # VIL-251 (2026-10-21) and VIL-380 (2026-10-22) both ran out ("Prompt is
        # too long") with the last turn near 109k. 192k leaves room for a 32k
        # reply inside LM Studio's 234k, which holds prompt and reply together.
        "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "196608",
        "DISABLE_AUTO_COMPACT": "1",
        # Qwen thinks before it acts, and its thinking counts as output. With an
        # 8k cap, a turn on 2026-10-21 thought for 9 minutes (28k characters),
        # hit the cap with no tool call, and was told to resume, losing that
        # thinking. 32k lets a long turn finish (about 25 minutes at worst, at
        # hal's ~20 tokens/s), so one request may take that long: API_TIMEOUT_MS
        # is 30 minutes, inside the worker's 60-minute limit.
        "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "32000",
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
        "API_TIMEOUT_MS": "1800000",
    })
    allowed = ["Read", "Edit", *WORKER_READONLY_BASH,
               *[f"Bash({c['cmd']})" for c in checks]]
    # stream-json (which needs --verbose) writes each event as it happens, so
    # a worker killed at the time limit still leaves its transcript.
    # --allowedTools is variadic, so it goes last; the prompt comes on stdin.
    cmd = ["claude", "-p", "--bare", "--tools", "Read,Edit,Bash",
           "--permission-mode", "dontAsk", "--no-session-persistence",
           "--output-format", "stream-json", "--verbose",
           "--allowedTools", *allowed]
    transcript = rundir / "worker.jsonl"
    t0 = time.monotonic()
    rc, _, err, killed = run_limited(cmd, wt, env, WORKER_TIMEOUT_S, brief,
                                     watch_memory=True, stdout_path=transcript)
    # Sampled before writing or parsing anything: timing.py ends a transcript
    # with no result event at ended_at, so it must be when the worker exited.
    duration_s = round(time.monotonic() - t0)
    ended_at = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    (rundir / "worker.stderr").write_text(err)
    with open(transcript, errors="replace") as fh:
        res = parse_stream(fh)
    usage = res.get("usage") or {}
    return {
        "ok": not killed and rc == 0 and not res.get("is_error"),
        "killed": killed,
        "exit": rc,
        "turns": res.get("num_turns"),
        "duration_s": duration_s,
        "ended_at": ended_at,
        "input_tokens": (usage.get("input_tokens", 0)
                         + usage.get("cache_read_input_tokens", 0)
                         + usage.get("cache_creation_input_tokens", 0)),
        "output_tokens": usage.get("output_tokens", 0),
        "summary": (res.get("result") or "")[-3000:],
    }


def run_checks(checks, wt, rundir):
    results = []
    with open(rundir / "checks.log", "w") as fh:
        for c in checks:
            t0 = time.monotonic()
            rc, out, err, killed = run_limited(
                ["/bin/bash", "-c", c["cmd"]], wt, dict(os.environ),
                CHECK_TIMEOUT_S)
            tail = (out + err)[-1500:]
            fh.write(f"### {c['name']}: {c['cmd']}\nexit {rc} {killed or ''}\n{out}{err}\n")
            results.append({**c, "ok": rc == 0 and not killed, "exit": rc,
                            "killed": killed, "tail": tail,
                            "secs": round(time.monotonic() - t0)})
    return results


def secret_scan(wt, base, rundir, env):
    """gitleaks over everything the push and the PR would publish: the run's
    commits (messages and patches) and the PR title and body. Returns None when
    clean, else what was flagged. Fails closed: a missing or erroring gitleaks
    counts as a finding."""
    # The worker can edit the checkout, and gitleaks always reads the scanned
    # tree's own .gitleaksignore (even with --gitleaks-ignore-path; tested on
    # 8.30.1). So the scan never runs on the checkout: the runner writes what
    # would be published into a directory it owns and scans that, with a trusted
    # config and gitleaks:allow comments ignored.
    scan = rundir / "scan"
    scan.mkdir(exist_ok=True)
    found = []
    try:
        log = subprocess.run(
            ["git", "-c", "core.quotepath=off", "log", "-p", "--no-color",
             "--format=commit %H%n%B", f"origin/{base}..HEAD"],
            cwd=wt, env=env, capture_output=True, text=True, errors="replace",
            timeout=300, check=True).stdout
    except (OSError, subprocess.SubprocessError) as e:
        return f"commits: couldn't export the run's commits ({e})"
    (scan / "commits.patch").write_text(log)
    for name in ("title.txt", "body.md"):
        shutil.copyfile(rundir / "pr" / name, scan / f"pr-{name}")
    cmd = ["gitleaks", "dir", "--config", str(HERE / "gitleaks.toml"),
           "--ignore-gitleaks-allow", "--redact", "--no-banner", str(scan)]
    # Not the git/gh env: gitleaks has no use for GH_TOKEN.
    clean_env = {k: v for k, v in env.items() if k != "GH_TOKEN"}
    with open(rundir / "gitleaks.log", "w") as fh:
        try:
            r = subprocess.run(cmd, cwd=scan, env=clean_env, capture_output=True,
                               text=True, timeout=300)
        except (OSError, subprocess.TimeoutExpired) as e:
            return f"gitleaks didn't run ({e})"
        fh.write(f"exit {r.returncode}\n{r.stdout}{r.stderr}\n")
        if r.returncode != 0:
            found.append(f"gitleaks exit {r.returncode} on the commits or PR text")
    return "; ".join(found) or None


def pr_body(ticket, plan_obj, worker, checks, run_id, failed_reasons):
    status = ("❌ **Failed:** " + "; ".join(failed_reasons)) if failed_reasons \
        else "✅ All acceptance checks passed."
    rows = "\n".join(
        f"| {'✅' if c['ok'] else '❌'} | {c['name']} | `{c['cmd']}` | {c['secs']}s |"
        for c in checks) or "| | (no checks ran) | | |"
    fails = "".join(
        f"\n<details><summary>{c['name']} output</summary>\n\n```\n{c['tail']}\n```\n</details>\n"
        for c in checks if not c["ok"])
    return f"""Pilot run `{run_id}` for {ticket['id']}: {ticket['title']}

{status}

Opened by the hal overnight runner (VIL-396). Not a draft, so the repo's automatic reviewer picks it up. The code was written by local `{WORKER_MODEL}`; the brief and checks by Opus. Nothing merges without David.

### Acceptance checks
| | Check | Command | Time |
|---|---|---|---|
{rows}
{fails}
### Run
- Worker: {worker.get('turns')} turns, {worker.get('duration_s')} s, {worker.get('input_tokens')} input / {worker.get('output_tokens')} output tokens{', stopped: ' + worker['killed'] if worker.get('killed') else ''}
- Planner: {plan_obj.get('_duration_s')} s, ${plan_obj.get('_cost_usd')} API-equivalent

<details><summary>Brief given to the worker</summary>

{plan_obj['brief']}
</details>

<details><summary>Worker's closing summary</summary>

{worker.get('summary') or '(none)'}
</details>

<details><summary>Ticket</summary>

{ticket['body']}
</details>
"""


def run_ticket(ticket, dry_run=False):
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    run_id = f"{ticket['id'].lower()}-{stamp}"
    branch = f"pilot/{run_id}"
    rundir = RUNS / "log" / run_id
    rundir.mkdir(parents=True, exist_ok=True)
    wt = RUNS / "work" / run_id
    env = git_env(read_secret("gh-token"))
    summary = {"run_id": run_id, "ticket": ticket["id"], "repo": ticket["repo"],
               "committed": False, "pushed": False}

    def finish(status, **extra):
        summary.update(status=status, **extra)
        (rundir / "run.json").write_text(json.dumps(summary, indent=2))
        log(f"{run_id}: {status}")
        return summary

    try:
        base = prepare_worktree(ticket["repo"], branch, wt, env)
        log(f"{run_id}: worktree {wt} on {branch} from {base}")
        # A broken environment isn't a broken change: no planner, no worker, no PR.
        why = sync_env(wt, rundir)
        if why:
            return finish("env-failed", error=why)
        if dry_run:
            return finish("dry-run")
        return run_stages(ticket, run_id, branch, base, wt, rundir, env, finish,
                          summary)
    except Exception as e:
        return finish("runner-error", error=str(e))
    finally:
        # An unpushed commit is the run's only copy of the work: keep its branch.
        keep = summary["committed"] and not summary["pushed"]
        if keep:
            log(f"{run_id}: push didn't happen; keeping local branch {branch}")
        cleanup_worktree(ticket["repo"], wt, branch, env, keep_branch=keep)


def run_stages(ticket, run_id, branch, base, wt, rundir, env, finish, summary):
    try:
        plan_obj = plan(ticket, wt, rundir)
    except Exception as e:
        return finish("planner-error", error=str(e))
    if plan_obj["proceed"]:
        # What the worker actually gets: brief.md and the PR body show this too.
        plan_obj["brief"] += bash_rules(plan_obj.get("checks") or [])
    (rundir / "brief.md").write_text(plan_obj["brief"])
    if not plan_obj["proceed"]:
        return finish("declined", reason=plan_obj["reason"])
    if disabled():
        return finish("disabled")

    worker = work(plan_obj["brief"], plan_obj["checks"], wt, rundir)
    changed = bool(git(["status", "--porcelain"], wt, env))
    # A worker stopped at the time limit may have finished the change and then
    # kept going, so its edits still get checked. The kill switch and low
    # memory mean stop now, so those skip the checks.
    timed_out = (worker["killed"] or "").startswith("timeout")
    run_them = not worker["killed"] or (timed_out and changed)
    checks = run_checks(plan_obj["checks"], wt, rundir) if run_them else []

    failed = []
    if not worker["ok"]:
        failed.append(f"worker {worker['killed'] or 'exit ' + str(worker['exit'])}")
    failed += [f"check `{c['name']}`" for c in checks if not c["ok"]]
    if not plan_obj["checks"]:
        failed.append("the plan had no acceptance checks")

    git(["add", "-A"], wt, env)
    if not git(["status", "--porcelain"], wt, env):
        failed.append("the worker changed no files")
        git(["commit", "--allow-empty", "-m",
             f"pilot: {ticket['id']} produced no changes\n\nPilot-Run: {run_id}"], wt, env)
    else:
        git(["commit", "-m",
             f"{plan_obj['pr_title']}\n\n{ticket['id']}\n\nPilot-Run: {run_id}\n"
             f"Worker-Model: {WORKER_MODEL}"], wt, env)

    summary["committed"] = True
    title = ("[pilot][failed] " if failed else "[pilot] ") + plan_obj["pr_title"]
    body = pr_body(ticket, plan_obj, worker, checks, run_id, failed)
    prdir = rundir / "pr"
    prdir.mkdir(exist_ok=True)
    (prdir / "body.md").write_text(body)
    (prdir / "title.txt").write_text(title + "\n")
    # dotfiles and browse-gateway are public, and so are their PRs: scan
    # before anything leaves hal. The local branch is kept for David to inspect.
    leak = secret_scan(wt, base, rundir, env)
    if leak:
        return finish("leak-blocked", leak=leak, failed=failed, worker=worker)
    git(["push", "origin", f"HEAD:refs/heads/{branch}"], wt, env)
    summary["pushed"] = True
    try:
        r = subprocess.run(
            ["gh", "pr", "create", "--repo", f"{OWNER}/{ticket['repo']}",
             "--base", base, "--head", branch, "--title", title,
             "--body-file", str(prdir / "body.md")],
            env=env, capture_output=True, text=True, timeout=120)
        pr_url = r.stdout.strip() if r.returncode == 0 else None
        pr_error = r.stderr.strip()[-2000:]
    except (OSError, subprocess.TimeoutExpired) as e:
        pr_url, pr_error = None, str(e)
    extra = dict(failed=failed, pr=pr_url, worker=worker,
                 planner_cost_usd=plan_obj.get("_cost_usd"))
    if not pr_url:
        # The branch is pushed; the PR can be opened by hand from pr/body.md.
        return finish("pr-failed", pr_error=pr_error, **extra)
    return finish("failed" if failed else "passed", **extra)


def cleanup_worktree(repo, wt, branch, env, keep_branch=False):
    """Remove the run's worktree and local branch; the pushed branch and the
    run log under ~/runs/log/ stay."""
    clone = RUNS / "repos" / repo
    if not clone.exists():
        return
    if wt.exists():
        git(["worktree", "remove", "--force", str(wt)], clone, env, check=False)
    if not keep_branch:
        git(["branch", "-D", branch], clone, env, check=False)


# ---------------------------------------------------------------- main

def gates():
    if disabled():
        return "kill switch is on (~/runs/DISABLED)"
    pct = free_memory_pct()
    if pct < MIN_FREE_PCT:
        return f"free memory {pct}% < {MIN_FREE_PCT}%"
    if not lmstudio_has_worker_model():
        return f"LM Studio is not serving {WORKER_MODEL}"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--once", action="store_true", help="run at most one ticket")
    ap.add_argument("--dry-run", action="store_true",
                    help="gates, worktree and dependency sync only; no models, no push")
    ap.add_argument("--ticket", type=Path, help="run this ticket file, not the queue")
    ap.add_argument("--max", type=int, default=MAX_TICKETS_PER_NIGHT,
                    help=f"most tickets to run (default {MAX_TICKETS_PER_NIGHT})")
    ap.add_argument("--ignore-window", action="store_true",
                    help="start tickets even after the morning cutoff")
    args = ap.parse_args()

    RUNS.mkdir(parents=True, exist_ok=True)
    RUNS.chmod(0o700)
    for d in ("queue", "log", "work", "repos"):
        (RUNS / d).mkdir(exist_ok=True)
    lock = open(RUNS / ".lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        log("another runner holds the lock; exiting")
        return 0
    pidfile = RUNS / "runner.pid"
    pidfile.write_text(str(os.getpid()))
    # On SIGTERM (kill.sh, launchd): stop the planner or worker, then exit
    # through the finally below, which removes the pid file.
    signal.signal(signal.SIGTERM, on_sigterm)
    try:
        return run_queue(args)
    finally:
        pidfile.unlink(missing_ok=True)


def run_queue(args):
    done = 0
    limit = 1 if (args.once or args.ticket) else args.max
    while done < limit:
        if not args.ignore_window and dt.datetime.now().time() >= STOP_STARTING_AT \
                and dt.datetime.now().time() < dt.time(18, 0):
            log("past the morning cutoff; not starting another ticket")
            break
        why = gates()
        if why:
            log(f"skip: {why}")
            break
        if args.ticket:
            ticket = parse_ticket(args.ticket)
        else:
            ticket = next_ticket()
            if not ticket:
                log("queue empty")
                break
            if not args.dry_run:
                ticket["path"] = shelve(ticket["path"], "taken")
        log(f"starting {ticket['id']} on {ticket['repo']}")
        s = run_ticket(ticket, dry_run=args.dry_run)
        done += 1
        if s["status"] == "planner-error":
            # Usually systemic (auth, timeouts): put the ticket back and stop.
            if not args.ticket:
                shelve_back(ticket["path"])
            log("planner failed; ticket requeued, stopping for the night")
            break
        if s["status"] == "env-failed":
            # Set aside, not requeued: a lasting cause (a broken lockfile) would otherwise
            # fail the same ticket first every night and block the queue behind it. Stop
            # anyway, since a passing one (the network) would fail the next ticket too.
            if not args.ticket and not args.dry_run:
                where = shelve(ticket["path"], "env-failed")
                log(f"dependency sync failed; ticket set aside as {where}, "
                    "stopping for the night")
            else:
                log("dependency sync failed; stopping")
            break
    return 0


if __name__ == "__main__":
    sys.exit(main())
