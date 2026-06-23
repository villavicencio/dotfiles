---
title: "Axiom's Claude Code does not survive a VPS reboot (systemd auto-launch + tmux launch-context race)"
date: 2026-06-22
category: cross-machine
module: axiom-vps
problem_type: integration_issue
component:
  - "/etc/systemd/system/axiom-tmux.service (+ .d/ drop-ins) on openclaw-prod"
  - "/usr/local/bin/axiom-wait-for-api"
  - "/usr/local/bin/axiom-claude-launch"
severity: High
tags:
  - axiom
  - vps
  - openclaw
  - systemd
  - tmux
  - claude-code
  - reboot
  - boot-order
  - network-online
  - send-keys
symptoms:
  - "AXIOM tmux pane comes up at a bare bash prompt after reboot with no claude process"
  - "`tmux ls` and `systemctl is-active axiom-tmux` both report healthy while claude is dead"
  - "claude exits silently during early boot because its startup call to api.anthropic.com fails"
  - "claude launched as tmux's direct command or via a non-interactive wrapper dies; only send-keys into a ready interactive pane survives"
  - "a fixed `sleep 1` before send-keys loses keystrokes that race the not-yet-ready shell"
root_cause: async_timing
resolution_type: config_change
related_issues:
  - "docs/solutions/cross-machine/vps-dotfiles-target.md (historical VPS sync runbook, retired 2026-05-21)"
  - "docs/solutions/code-quality/zsh-dash-i-c-exit-false-positive-health-check.md (adjacent early-boot false-positive on the same VPS)"
  - "auto-memory: axiom-vps-claude-lifecycle, axiom-vps-dotfiles-clone"
---

# Axiom's Claude Code does not survive a VPS reboot (systemd auto-launch + tmux launch-context race)

## Problem

Axiom's Claude Code session (`claude --continue`), auto-started by the `axiom-tmux.service` systemd unit on the VPS `openclaw-prod` (Ubuntu 24.04, systemd-networkd, native Claude Code binary at `/home/axiom/.local/bin/claude`), did not survive a reboot. After the box came back, the AXIOM tmux pane sat at a bare bash prompt with no `claude` process — the unattended agent that should have been there on boot simply wasn't.

## Symptoms

The failure was quiet and actively misleading — every coarse health check reported green while the agent was dead:

- **Bare pane after reboot.** The AXIOM pane shows `axiom@openclaw-prod-hil:~/work$` instead of the Claude TUI.
- **`tmux ls` looks healthy.** The AXIOM session is listed, because the tmux *session* survives even when its child `claude` has exited.
- **`systemctl is-active axiom-tmux` reports `active`.** Type=forking + the tmux server staying up means systemd sees the service as started.
- **The obvious detection grep gives a false positive.** `ps -u axiom | grep claude` matches the launcher's own argv (`tmux new-session … claude --continue`), so a naive check "confirms" claude is running when it is not.

Reliable detection must exclude the launcher's own command line:

```bash
# False positive — matches "tmux new-session ... claude --continue"
ps -u axiom | grep claude

# Correct — exclude the launcher argv
ps -u axiom -o pid,ppid,args | grep -- 'claude --continue' | grep -v 'tmux new-session'
```

## What Didn't Work

Each of these was tried and rejected, in order. The dead ends are the useful part — they rule out the "obvious" fixes.

1. **`After=`/`Wants=network-online.target` alone.** "Online" means the interface has an address and route, not that outbound is usable. claude still died in the early-boot transient.
2. **Enabling `systemd-time-wait-sync` + gating on `time-sync.target`.** The unit then started right after clock sync — but claude *still* died. The clock was never the cause; sync time merely correlated with the network settling. A proxy for the dependency, not the dependency.
3. **A retry wrapper script as the tmux session's command** (claude as a child of a non-interactive bash loop). Made it *worse*: the pane fell to `-bash` and the wrapper died after a single logged attempt. Confirms the launch-context cause below.
4. **Reverting to a direct `ExecStart` + an `ExecStartPre` wait.** Still died on a fully-booted manual `systemctl restart` — claude as tmux's *direct command* is fragile when invoked from the service context, even though the identical tmux command run by hand worked. This was the clue that the launch *method*, not just timing, mattered.
5. **The diagnostic that cracked it.** Running, by hand, into a ready pane — `sudo -u axiom tmux send-keys -t AXIOM "claude --continue" Enter` — worked every single time. Meanwhile the launcher's `sleep 1` + send-keys left a clean prompt with no echoed command, proving the keystrokes were **lost to a race** against a not-yet-ready shell, not a deep crash.

## Solution

Two compounding problems had to be fixed together — addressing either alone left claude dying on boot.

**Cause 1 — early-boot connectivity transient.** `network-online.target` does not mean `api.anthropic.com` is reachable. The smoking gun was in journald from `systemd-timesyncd`, which hit the same wall: `network-online.target` was reached at `18:55:32`, but timesyncd logged repeated `Network configuration changed, trying to establish connection` and did not contact its NTP server until `18:56:08` — ~33s later. claude's startup HTTPS call landed in that dead window, failed, and claude exited.

**Cause 2 — launch context.** claude survives only when launched by `tmux send-keys` into an already-ready interactive bash pane (job control + a real controlling terminal). As tmux's direct command, via a non-interactive wrapper, or with a fixed `sleep 1` before send-keys, it dies or the keystrokes are silently dropped.

The fix: systemd drop-ins under `/etc/systemd/system/axiom-tmux.service.d/` plus two helper scripts. Gate on the *real* reachability dependency, and launch via the one method proven to keep claude alive.

`/etc/systemd/system/axiom-tmux.service.d/10-network-online.conf`:

```ini
[Unit]
After=network-online.target time-sync.target
Wants=network-online.target time-sync.target
```

`/etc/systemd/system/axiom-tmux.service.d/30-wait-for-api.conf` (the empty `ExecStart=` resets the unit's original command before setting the new one):

```ini
[Service]
ExecStartPre=/usr/local/bin/axiom-wait-for-api
ExecStart=
ExecStart=/usr/local/bin/axiom-claude-launch
TimeoutStartSec=240
```

`/usr/local/bin/axiom-wait-for-api` — block until `api.anthropic.com:443` is genuinely reachable (DNS resolves **and** the TCP socket opens), bounded so it can never hang boot forever:

```bash
#!/bin/bash
# axiom-wait-for-api — block until api.anthropic.com is resolvable AND reachable
# on 443, so claude --continue doesn't start in the early-boot window where
# DNS/outbound isn't ready yet and exits. Bounded (~3 min) so it never blocks boot.
host="api.anthropic.com"
for i in $(seq 1 60); do
  if getent hosts "$host" >/dev/null 2>&1 && (exec 3<>"/dev/tcp/$host/443") 2>/dev/null; then
    exec 3>&- 2>/dev/null
    echo "axiom-wait-for-api: $host reachable after $i check(s)"
    exit 0
  fi
  sleep 3
done
echo "axiom-wait-for-api: gave up after ~180s, launching anyway"
exit 0
```

`/usr/local/bin/axiom-claude-launch` — replicate the only launch method that keeps claude alive: send-keys into a *ready* pane, after polling `pane_current_command` (never a fixed sleep), with verify-and-retry:

```bash
#!/bin/bash
# axiom-claude-launch — bring up claude in the AXIOM tmux session by send-keys
# into a READY interactive bash pane (the only method that keeps claude alive),
# after the ExecStartPre wait-for-api gate has confirmed connectivity.
SESS=AXIOM
tmux has-session -t "$SESS" 2>/dev/null || tmux new-session -d -s "$SESS" -c /home/axiom/work
# already running? nothing to do
pgrep -u axiom -f "claude --continue" >/dev/null 2>&1 && exit 0
# wait for the pane's shell to be ready to receive input (never a fixed sleep)
for i in $(seq 1 30); do
  [ "$(tmux display -p -t "$SESS" '#{pane_current_command}' 2>/dev/null)" = "bash" ] && break
  sleep 1
done
sleep 2
# send the command, retrying in case a keystroke is still lost to a race
for attempt in 1 2 3; do
  pgrep -u axiom -f "claude --continue" >/dev/null 2>&1 && break
  tmux send-keys -t "$SESS" "claude --continue" Enter
  sleep 8
done
```

Install and validate with a **real reboot** (not just `systemctl restart`):

```bash
systemctl enable systemd-time-wait-sync   # makes time-sync.target meaningful
systemctl daemon-reload
reboot
```

Validated by an actual reboot: claude returned **unattended** — its PID inside the `axiom-tmux.service` cgroup, full TUI rendered in the AXIOM pane, resumed to the working prompt.

## Why This Works

- **`axiom-wait-for-api` blocks on the actual dependency.** Instead of guessing with `network-online.target` or the `time-sync.target` proxy, the `ExecStartPre` gate does not return until a real TCP connection to `api.anthropic.com:443` opens, so claude's startup call never lands in the dead window (Cause 1). The loop is bounded and exits 0 on timeout, so a genuinely-down network degrades gracefully instead of wedging boot.
- **`axiom-claude-launch` uses the one method proven to survive.** It reproduces the hand-run send-keys-into-a-ready-pane path: an interactive bash pane with job control and a real controlling terminal — the only context where claude stays alive (Cause 2).
- **Polling `pane_current_command` kills the race.** Waiting until the pane's command is actually `bash` (instead of a blind `sleep 1`) guarantees the shell can receive the keystrokes; the post-launch verify-and-retry catches residual flakiness.
- **`TimeoutStartSec=240`** gives the wait plus the launch poll headroom so systemd doesn't kill the unit mid-startup.

## Prevention

For any TUI or long-running agent auto-started under systemd in a detached tmux session:

1. **Gate on the real reachability dependency, not `network-online.target`.** Block in `ExecStartPre` until the actual host:port you depend on accepts a connection.
2. **Launch interactive TUIs via `send-keys` into a ready shell pane** — never as tmux's direct command and never via a non-interactive wrapper. TUIs need a real controlling terminal with job control.
3. **Wait for `pane_current_command` to be the shell before `send-keys` — never a fixed `sleep`.** Then verify the process came up and retry. A blind sleep races the shell and silently drops keystrokes.
4. **When checking "is it running," exclude the launcher's own argv from the grep.** `tmux new-session … claude` matches a naive `grep claude`.
5. **Know the unattended-resume limit.** For a large/old session, `claude --continue` still parks at a "Resume from summary / full" menu awaiting input — even a flawless auto-launch will not fully resume a big session unattended. The TUI comes up; the conversation doesn't continue on its own.

## Related Issues

- `docs/solutions/cross-machine/vps-dotfiles-target.md` — historical VPS dotfiles sync runbook (retired 2026-05-21); preserves the design for future Linux hosts. This fix is orthogonal to that sync workflow.
- `docs/solutions/code-quality/zsh-dash-i-c-exit-false-positive-health-check.md` — adjacent early-boot false-positive health check on the same VPS; both defend against silent bootstrap-state misdiagnosis.
- Prior reboot-triggered VPS connectivity issue: a Tailscale peer-list re-registration race after reboot (closed GitHub issue) — same family of "network nominally up, not actually usable yet" problems.
- Auto-memory: `axiom-vps-claude-lifecycle` (attach/detach/update lifecycle, now records this fix), `axiom-vps-dotfiles-clone` (settings overlay + sync-dotfiles).
