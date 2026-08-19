---
title: "launchd services execute with a bare environment — user-PATH commands die silently and probe panels lie"
date: 2026-08-18
category: integration-issues
module: herdr
problem_type: integration_issue
component: tooling
severity: Medium
symptoms:
  - "A [[keys.command]] shell binding in herdr does nothing on keypress — no error, no log line — yet the same command works in a terminal"
  - "herdr's settings→integrations panel reports an installed CLI (codex at /opt/homebrew/bin/codex) as \"not found\""
  - "Behavior differs between a brew-services-managed process and the same tool launched from a shell"
root_cause: design_limitation
resolution_type: config_change
related_components:
  - infrastructure
  - development_workflow
tags:
  - launchd
  - brew-services
  - path
  - silent-failure
  - herdr
  - macos
  - environment
---

# launchd services execute with a bare environment — user-PATH commands die silently and probe panels lie

## Problem

Anything a launchd-managed service (`brew services start <formula>`) spawns or probes runs with launchd's bare environment — PATH is the system default (`/usr/bin:/bin:/usr/sbin:/sbin`), with no `/opt/homebrew/bin` and none of the user's shell setup. Commands that rely on the interactive PATH fail with command-not-found, and because service-spawned work is typically detached, the failure surfaces nowhere.

## Symptoms

- Herdr `[[keys.command]]` bindings with `type = "shell"` appeared completely dead: keypress → nothing, and nothing in `~/.config/herdr/herdr-server.log` (herdr does not log shell spawns or their failures at all).
- Herdr's settings→integrations panel showed `codex — not found` while `/opt/homebrew/bin/codex` was installed and `herdr integration status` from a login shell reported it correctly — the panel probes with the server's PATH.
- The same commands worked instantly when run from any interactive shell, which made the service look broken rather than the environment.

## What Didn't Work

- **Reading the server log for dispatch evidence** — herdr never logs this event class, so absence proved nothing (this false trail was mis-filed upstream and later corrected; see the companion methodology write-up below).
- **Reloading and even restarting the server** to "activate" the bindings — they were dispatching the whole time; their spawned commands were dying on PATH.

## Solution

Use absolute paths in anything a launchd service will execute:

```toml
# herdr/config.toml — BEFORE (dies silently under the service):
[[keys.command]]
key = "prefix+a"
type = "shell"
command = "herdr agent focus atlas"

# AFTER (works immediately, plain reload-config applies it):
[[keys.command]]
key = "prefix+a"
type = "shell"
command = "/opt/homebrew/bin/herdr agent focus atlas"
```

Both Macs are ARM, so `/opt/homebrew` is stable across machines in this repo (an Intel machine would need `/usr/local`). For status questions, trust a login-shell command (`herdr integration status`) over any server-rendered panel.

## Why This Works

launchd does not source shell profiles; services inherit launchd's minimal environment by design. Every child process and every probe the service performs sees that environment. An absolute path removes the one lookup that depended on the user's shell context. The failure is silent specifically because service-spawned commands are detached — there is no terminal to print `command not found` to, and (in herdr 0.8.0) no logging of the spawn or its exit.

## Prevention

- **Rule: any command string written into config that a service executes gets an absolute path** — herdr key commands, notify hooks, watchers, anything under `brew services`. When in doubt, `command -v <tool>` in a shell and paste the result.
- **Calibrate before trusting a "not found" or "dead binding" symptom from a service**: probe the service's actual environment in-band, e.g. bind a throwaway command `"/bin/sh -c 'env > /tmp/svc-env'"` and read the dump — it shows exactly what PATH the service resolves against.
- **Panel/UI probes that run inside the server are not authoritative** about what's installed on the machine. Shell-side equivalents are.
- Known family members on this machine: sudo under no-TTY agent shells needs Touch ID (`docs/solutions/security/sudo-in-no-tty-agent-shells-touch-id-2026-08-07.md` — same "service/agent context differs invisibly from your terminal" class), and upstream [herdrdev/herdr#2960](https://github.com/herdrdev/herdr/issues/2960) asks herdr to spawn with the user's login environment or surface exec failures.

## Related Issues

- Companion methodology write-up (how the silent failure masqueraded as two different "dead feature" bugs and how in-band probes settled it): `../best-practices/verify-the-instrument-before-trusting-a-negative.md`
- Upstream: [herdrdev/herdr#2960](https://github.com/herdrdev/herdr/issues/2960) — retitled to this exact defect after the misdiagnosis was corrected.
- Repo changes: PR #142 (absolute paths in `herdr/config.toml` + corrected CLAUDE.md/AGENTS.md gotchas).
