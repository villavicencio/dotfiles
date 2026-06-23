# HANDOFF — 2026-06-22 (evening PDT)

Same-session continuation from the June 12 handoff. Started with `/pickup`, worked
handoff item 2 (NODE_ENV), then the session pivoted into VPS operations on
`openclaw-prod` — a mosh install, a health check that surfaced a pending kernel
reboot, and a deep multi-hour debugging arc to make Axiom's Claude Code survive a
reboot unattended. Closed with a Ship Sigma deliverability page update (deployed)
and a `/ce-compound` documenting the reboot fix. Board empty, no open PRs, working
tree clean.

## What We Built

**dotfiles repo (all merged to master):**
- **PR #93** — removed the global `export NODE_ENV=development` from `zsh/zshenv:145`
  (was poisoning `next build` etc.); updated the integration-issues solution doc's
  Prevention note to record the removal.
- **PR #94** — recorded `claude/settings.json` baseline: model pin `opus[1m]`, enabled
  vercel + skill-creator plugins, `skipWorkflowUsageWarning`. (Reminder: this file is
  rewritten by `/model` and `/effort` at runtime, so it goes dirty again after use.)
- **028aee0** — new solution doc
  `docs/solutions/cross-machine/axiom-claude-not-surviving-vps-reboot-systemd-tmux.md`
  (via `/ce-compound`): the two-part root cause, the dead-end trail, and the final fix.

**VPS `openclaw-prod` (Ubuntu 24.04, Hetzner):**
- **mosh 1.4.0 installed.** Attach alternative: `mosh root@openclaw-prod -- sudo -u axiom
  tmux attach -t AXIOM`. Works over Tailscale with zero firewall changes (UFW inactive;
  MagicDNS → 100.x; mosh UDP rides inside WireGuard).
- **4 GiB swapfile** created + persisted in `/etc/fstab` (was `0B` swap before).
- **Kernel updated** — pending `6.8.0-124` applied via reboot; reboot flag cleared.
- **axiom-tmux reboot-survival FIXED + validated.** claude now returns unattended after
  reboot. Fix = systemd drop-ins under `/etc/systemd/system/axiom-tmux.service.d/`:
  - `10-network-online.conf`: `After=/Wants=network-online.target time-sync.target`
    (+ `systemctl enable systemd-time-wait-sync`).
  - `30-wait-for-api.conf`: `ExecStartPre=/usr/local/bin/axiom-wait-for-api`,
    `ExecStart=/usr/local/bin/axiom-claude-launch`, `TimeoutStartSec=240`.
  - `/usr/local/bin/axiom-wait-for-api` — blocks until `api.anthropic.com:443` reachable.
  - `/usr/local/bin/axiom-claude-launch` — creates AXIOM shell session, waits for the
    pane shell to be ready, then `send-keys "claude --continue"` with retry.

**davidv.sh (deployed live, commit `63ba935`, Vercel `dpl_GBJ4PBB…` READY):**
- Ship Sigma `/ops/shipsigma-deliverability` page: kept the 8-inbox framing, reframed
  strategy to *maintain* volume via added capacity (not cut it), Phase-1 changed from
  "pause heavy senders" to "throttle to safe ceiling," and added how to measure the
  aggregate daily volume (M365 message trace). Calculator left at illustrative 200.

**Memory updated:** `axiom-vps-claude-lifecycle` now carries the corrected two-part root
cause + the final fix (replacing the earlier wrong network-online-only theory) and the
mosh attach option.

## Decisions Made
- **Reboot-survival root cause is TWO things, not one:** (1) early-boot connectivity
  transient — `api.anthropic.com` not reachable for ~30s+ even after `network-online.target`
  (proven: timesyncd couldn't reach NTP until +33s); (2) claude only survives launched by
  `send-keys` into a READY interactive bash pane, never as tmux's direct command or via a
  non-interactive script. Fix had to address both.
- **Gate on real reachability (`wait-for-api`), not proxies.** network-online and clock-sync
  gates were each tried and were insufficient on their own.
- **Ship Sigma: maintain volume, don't cut it** (user directive) — so the page now sizes
  dedicated infra to carry current volume rather than recommending a volume cap. Aggregate
  daily number is still unmeasured; user said move on without it.
- **New solution docs go straight to master** (additive content), per standing preference —
  no branch/PR for the `/ce-compound` doc.

## What Didn't Work
- **network-online.target gate alone** — "online" = interface has an address, not that
  outbound works. claude still died.
- **systemd-time-wait-sync + time-sync.target gate** — unit started right after clock sync,
  claude still died. Clock was a correlate, not the cause.
- **Retry wrapper as the tmux session command** (claude as child of a non-interactive bash
  loop) — made it worse; pane fell to `-bash`, wrapper died after one attempt.
- **Direct ExecStart + ExecStartPre wait** — still died on a fully-booted `systemctl restart`;
  claude-as-tmux-direct-command is fragile from the service context.
- The breakthrough: manual `send-keys` into a READY pane worked every time; the launcher's
  `sleep 1`+send-keys lost keystrokes (clean prompt, no echoed command) → it was a send-keys
  race, not a deep crash.

## What's Next
1. **Measure Ship Sigma's aggregate daily send volume** across the 8 inboxes (M365 message
   trace / sending-platform stats) → plug into the `/ops/shipsigma-deliverability` calculator,
   which is still at the illustrative 200 default. The page tells the user how to get it.
2. **Optional: buy `villavi.dev`** ($9.99/$13) as the sayable alias (carried from June 12).
3. **Dec 11, 2026** — calendar event fires to revisit the davidv.sh 307→308 redirect flip.

## Gotchas & Watch-outs
- **axiom reboot-survival is validated but new** — if a future reboot ever strands claude
  again, the next suspect beyond what's fixed is DNS-resolver-specific readiness. Detection
  gotcha: `ps | grep claude` matches the tmux launcher's argv — always
  `grep -v "tmux new-session"`. And `tmux ls` / `systemctl is-active` look healthy even when
  claude is dead; check for an actual claude PID.
- **Large-session resume caveat** — even with the fix, `claude --continue` parks at a
  "Resume from summary / full" menu for a big session; a perfect auto-launch still won't fully
  resume a large session unattended (someone must pick).
- **axiom settings.json is generated** — edit `~/.claude/settings.overlay.jq`, sync via
  `sync-dotfiles`; never edit the file directly. (Unchanged from before.)
- **Don't launch claude ad-hoc on the VPS** (`su - axiom` → claude) — everything via the
  AXIOM pane. (Unchanged.)
- **`claude/settings.json` will keep going dirty** as `/model` and `/effort` write to it —
  expected churn, not a problem; commit a fresh baseline when it matters.
- **davidv.sh framework preset must stay `nextjs`**; this deploy was content-only MDX so no
  preset risk. `OPS_SECRET` lives only in Vercel env + untracked `.env.local`.
