# HANDOFF — 2026-04-22 (continuation of 2026-04-21 session, crossed midnight PST)

## What We Built

### Shipped to master (3 direct-push commits, no PRs)

**`d5cd1b3` — uppercase LOCAL/VPS in status-left session pill.** Format-level ternary enumeration in `tmux/tmux.display.conf:49`: `#{?#{==:#S,local},LOCAL,#{?#{==:#S,vps},VPS,#S}}`. Zero subprocess cost, falls through to raw `#S` for any session name other than the two knowns. First attempt tried `#{upper:#W}` but that modifier doesn't exist in tmux next-3.7 — rendered literal `upper:<value>` and made window names "disappear" (user saw the literal string `upper:dotfiles` etc.). Reverted immediately and switched to ternary.

**`ba18518` — sage-green VPS session pill for visual host distinction.** Mac stays on vivid blue `#2563EB` with white fg; VPS gets One Dark green `#98C379` with dark fg `#031B21`. Selected by session-name ternary on both `bg=` and `fg=` attributes. Intent: an ssh'd-in tmux session is instantly recognizable at a glance before typing anything destructive. Inline config comment documents the `##`-escape rule for future editors. VPS pill renders on next `tmux source-file` / reattach over there.

**`2c38a68` — solution doc for the tmux format-string escape gotcha.** Path: `docs/solutions/code-quality/tmux-format-hex-mangled-by-single-char-escape-2026-04-21.md`. Written via `/ce:compound` full-mode workflow (4 parallel subagents including session historian). Covers diagnosis via `tmux display-message -p`, before/after code, prevention checklist, and cross-links to the PUA-glyphs doc (same meta-pattern) and the bare-index-target gotcha (sibling tmux doc).

### Operational events (not commits)

- **VPS sync action triggered twice** — both `apply` mode, successful. Run IDs `24752335727` (d5cd1b3, 24s) and `24752942455` (ba18518, 45s). Both pushed via `gh workflow run sync-vps.yml -f host=openclaw-prod -f dry_run=false`. Confirmed VPS landed on `2c38a68` via `ssh root@openclaw-prod 'cd ~/.dotfiles && git log --oneline -1'`.
- **Forge inbox processed at /pickup.** One message — OpenClaw MCP-reaper killed 40 stale subprocesses in one run (threshold 25). Archived; carry-forward to OpenClaw-side investigation. Not dotfiles-scoped.
- **Direct-to-master push pattern** — user opted against PR for these three changes ("fairly straightforward change"). That's why the sync action didn't auto-trigger initially — it's `workflow_dispatch`-only, not branch/push-triggered, so PR vs direct-push has no effect on sync.

## Decisions Made

- **Solution doc lives under `code-quality/`, not `ui-bugs/`.** Context Analyzer subagent flagged that the schema maps `ui_bug` problem_type → `ui-bugs/`, but every neighboring tmux gotcha (PUA glyphs, bare-index target) is already in `code-quality/` as legacy placement. Chose legacy-consistency over schema-strictness so the new doc is discoverable alongside its siblings. Trade-off acknowledged inline.
- **Sage green `#98C379` from the One Dark palette, not an arbitrary "soothing green."** Matches the existing theme colors (PREFIX pill `#7DACD3`, COPY `#E5C07B`, SYNC `#C98389` are all One Dark semantic colors). Dark fg `#031B21` mirrors the other light-bg pills so contrast is consistent.
- **VPS-only green; Mac stays vivid blue.** Interpreted "soothing green" as a VPS-pill-only change, not a full restyle. Two-tone encoding (vivid-blue for local, muted-sage for VPS) preserves the attention gradient — blue stays "default, eye-catching" and green says "elsewhere, calm-signal."
- **Ternary enumeration for case conversion.** After discovering `#{upper:...}` doesn't exist in tmux, chose explicit `#{?#{==:#S,local},LOCAL,...}` over any subprocess approach (`#(...)` with `tr`, etc.). Pure format-string, no fork per status-redraw (every 1s). Handles exactly the two known sessions and falls through cleanly.
- **Straight-to-master for trivial config tweaks.** User explicitly opted out of PR workflow for these three commits. The existing rule ("always branch for ticket work") still holds — this was ad-hoc, not ticket-sourced.
- **`/ce:compound` in Full mode with session history.** Dispatched 4 parallel subagents (Context Analyzer, Solution Extractor, Related Docs Finder, Session Historian). Historian confirmed first-encounter for this bug — no prior failed attempts across 14 Claude Code + 3 Codex sessions dating back to 2026-04-09.

## What Didn't Work

- **`#{upper:#W}` for uppercase window names.** First interpretation of "tmux labels uppercase" — wrapped `#W` in `#{upper:...}` in both window-status-format and window-status-current-format. Tmux rendered the literal string `upper:<window-name>`, which is why the user said "the window names disappeared" (they were shown as `upper:nvim` etc., clipped by tab width). Reverted both lines before investigating the right target. **Reason it failed:** `#{upper:...}` / `#{lower:...}` aren't actual tmux format modifiers (verified on both tmux next-3.7 locally and tmux 3.4 on VPS). The parser treats `upper:` as an unknown modifier and renders it as literal text + the resolved value.
- **Bare hex colors inside ternary branches.** First version of the green pill used `#[bg=#{?#{==:#S,vps},#98C379,#2563EB}#,fg=#{?#{==:#S,vps},#031B21,#FFFFFF}#,bold]`. Pill rendered colorless. Diagnosis with `tmux display-message -p` showed `fg=*FFFFF` — the `#F` in `#FFFFFF` got consumed as the window-flags format escape. Reverted, ##-escaped all four hex literals inside the ternaries, re-applied. Clean.
- **Nearly shipped a broken pill state.** User caught the colorless render before commit because of the "test before committing" rule. Without that guardrail, the broken state would have landed. The solution doc now documents the diagnostic so future encounters catch it faster, but the organizational rule (test first) is still the load-bearing safeguard.

## What's Next

Prioritized:

1. **Next VPS reattach picks up the green pill.** No urgent action — the config file on the VPS is already synced (`2c38a68`), just needs `tmux source-file ~/.config/tmux/tmux.conf` or a client reattach to re-render. Cheap visual confirmation when you next ssh in.
2. **First live editor of the tmux format ternaries will encounter the `##`-escape rule.** The inline comment above `status-left` in `tmux/tmux.display.conf` documents it. If someone adds another conditional color without `##`, pill color breaks silently. Low-probability but captured in the solution doc.
3. **Still open from yesterday's handoff** (no change): OpenClaw gateway MCP-reaper leak (not dotfiles — 2026-04-21 inbox noted 40 kills vs. 25 threshold, archived), Syncthing healthcheck misconfig (not dotfiles), OAuth rotation reminder (2027-04-14 calendar). No new dotfiles-scoped items on the board.

## Gotchas & Watch-outs

- **`#{upper:...}` and `#{lower:...}` do NOT work in tmux next-3.7 OR tmux 3.4.** Both tested in this session. If you want case-conversion in a format string, use a ternary or rename the source (session name, window name, etc.). Subprocess (`#(...)` with `tr`) works but costs a fork per status-redraw.
- **Any hex color inside a `#{?...}` ternary MUST be `##RRGGBB`.** Single-char format escapes (`#F` = window flags, `#D` = pane id, `#S` = session, `#H` = host, `#T` = title, `#I` = index, `#P` = pane index, `#W` = window name) are evaluated during ternary-branch expansion, so they consume the leading char of a bare hex and silently mangle the color. Failure is silent — no error on `tmux source-file`, just a colorless pill. Inline comment now lives above the `status-left` block; the solution doc captures the full pattern.
- **`tmux display-message -p '<format-string>'` is the canonical diagnostic for format-string issues.** Returns post-expansion text before the style engine parses attributes. If a hex looks mangled in that output (`*FFFFF` instead of `#FFFFFF`), you have an escape-order problem.
- **Straight-to-master pushes DO NOT auto-trigger `sync-vps.yml`.** The workflow is `workflow_dispatch`-only; no push/branch/PR trigger exists. User initially thought the sync didn't run because of direct-push — actually it never auto-runs regardless. Trigger explicitly with `gh workflow run sync-vps.yml -f host=openclaw-prod -f dry_run=false` (or `dry_run=true` for preview).
- **Carry-forward from yesterday:** `/handoff` skill may render stale paths after a mid-session edit to the skill file. Not hit this session but the rule stands — `/clear` before invoking if the skill file changed during the session.
