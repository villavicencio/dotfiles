# HANDOFF — 2026-06-02 07:24 (PDT)

Continuation session that opened with `/pickup`. The dirty-tree blocker from the prior
handoff (the `/reload-skills` reddit/twitter/critique migration) turned out to be **already
resolved** — committed as `3a898a8` before this session's first real work. The bulk of this
session was a long, iterative **statusline redesign** (many small visual rounds with the user),
ending in a slider-bar look, plus **adopting a branch + pull-request workflow** for the repo.

## What We Built

**Statusline (`claude/statusline-command.sh`) — all on `master`, pushed:**
- **`700d594`** `style(statusline)` — dropped the implied " context" from the model descriptor
  (`1M context` → `1M`); unified the `/effort` token color with the descriptor (both soft gold).
- **`3764a12`** `feat(statusline)` — added worktree badge, PR badge (OSC 8-linked), session
  line-delta, and 5h/7d rate-limit meters; refactored to a **single `jq` pass** (12 fields,
  joined with `0x1F`).
- **`f89505f`** `feat(statusline)` — **two-line layout**: line 1 = location/git (folder, dir,
  worktree, branch, line-delta, PR), line 2 = model + meters. Dropped the `|` separators (line
  break separates the groups); meters lost the `:` (`ctx 12%`).
- **`a2c22a4`** `feat(statusline)` — battery fuel-gauge on meters (later superseded).
- **`8453a40`** `feat(statusline)` — **folder glyph** (U+F07B, cyan) leading line 1; replaced
  the battery with a **slider bar** (`▓` fill / `│` cursor U+2502 / `░` track), truecolor
  lime/amber/salmon, article thresholds (green <50 / yellow 50-70 / red >70), 10 cells, dim label.
- **`e60f646`** `style(statusline)` — **undimmed** the `ctx`/`5h`/`7d` labels (dim gray → white)
  per user; branch and PR-state keep their dim.

**Final line-2 look:** `Opus 4.8 (1M, xhigh)  ctx ▓▓▓▓│░░░░░ 35%  5h ▓▓▓▓▓▓│░░░ 58%  7d …` (~79 cols).

**Workflow adoption — PR #83, OPEN/UNMERGED:**
- **`6bbeb72`** (branch `chore/adopt-branch-pr-workflow`) — `docs:` adds a "Branching & pull
  requests" section to repo-root `CLAUDE.md`: branch-per-change with conventional names, one PR
  per logical change via `gh`, merge→delete-branch→close-issue, trivial-doc carve-out.
  PR: https://github.com/villavicencio/dotfiles/pull/83

## Decisions Made

- **Two-line statusline** (location/git over engine/meters) — chosen over a tightened single line.
- **Slider bar over block bars.** Hard constraint surfaced: in one terminal cell, block width and
  gap are zero-sum, and you can't have {10 cells + wide blocks + 3 bars} simultaneously (~100+
  cols, wraps). Sliders are one char/cell, so all three meters fit. The `│` cursor glyph came
  from reading ccstatusline's `makeSliderBar` source.
- **Color thresholds** adopted from the source article: green <50, yellow 50-70, red >70, in
  brighter truecolor lime/amber/salmon. Meter **labels are white** (undimmed); bar fill + % carry
  the threshold color; track is dim gray.
- **Branch + PR is now the default workflow** (PR #83). Generalizes the prior "tickets get a
  branch" rule to all behavior/config changes; trivial doc tweaks (incl. HANDOFF.md) may still go
  straight to `master`.
- **HANDOFF.md lives on `master`**, not feature branches (session-state doc; trivial-doc carve-out).

## What Didn't Work

The statusline bar went through a long glyph odyssey — **do not relitigate these:**
- `■` (U+25A0) / `` (FA square) solid glyphs → render **contiguous** (no gaps) in the
  user's Nerd Font; user disliked.
- `▉` (7/8 block) → "tiny tiny gap," rejected as too small.
- Spaced FA squares (` `) → correct gaps but line 2 → **103 cols** (wraps).
- `██` double-width + space, 8 cells → **118 cols**, way too wide.
- Partial-block ladder (`▊`/`▋`/`▌`) → can't satisfy wide-blocks + gaps + 10-cells + 3-bars (the
  zero-sum-within-a-cell constraint). 3-4 fat cells fit but were too coarse.
- Dot `·` divider between segments → user said "ugly," reverted.
- **ccstatusline source** uses `█/░` (progress) or `▓/░` (slider) — both contiguous; the reference
  images' gapped-square look is font-dependent/custom, not reproducible 1:1 in the user's font.

## What's Next

1. **Merge PR #83** (branch+PR workflow). Then `git checkout master && git pull`, delete the
   local + remote branch. (Currently checked out on `master`; the branch is pushed.)
2. **Update the compound-engineering plugin** — on **v3.9.2**, **v3.9.4** available:
   `claude plugin update compound-engineering@compound-engineering-plugin`, then restart Claude Code.
3. **Board tickets, now via branch+PR per the new convention:** **#81** (zoxide + eza — quick
   additive) and **#82** (delta + atuin — needs the delta-vs-`vim -` pager and atuin-history
   decisions first).
4. Optional: squash the 6 statusline commits on `master` into one if you want tidier history
   (offered, not done — it's all working and pushed).

## Gotchas & Watch-outs

- **⚠️ `0x1F` jq delimiter trap.** The single-`jq` parse joins fields with `join("")`. The
  **Write tool silently injects a literal `0x1F` byte** if you type `join("")` — twice this
  session it had to be fixed via a Python replace. After any edit near that line, `grep "join"
  claude/statusline-command.sh | cat -v` and confirm it reads ``, not `^_`.
- **Glyphs must be octal-encoded** in the script (`\357\203\210` etc.) — never literal PUA chars
  (Write tool strips them) and never `\xHH`/`\uXXXX` (dash prints them literally). See
  `docs/solutions/code-quality/claude-code-bash-tool-strips-pua-glyphs.md`.
- **Two `SC2059` inline-disabled** (branch + PR glyph printfs). The suggested `%s` fix **breaks**
  them — the color vars hold literal `\033` escape strings that must sit in the printf *format*
  to be interpreted. Don't "fix." `shellcheck -s sh` is otherwise clean.
- **Statusline is symlinked/live** — edits take effect on the next refresh; verify visual changes
  by looking at the actual statusline (the user screenshots), since rendering is font-dependent
  and can't be confirmed from stripped output here.
- **gitleaks pre-commit** stashes unstaged files on every commit (the dangling `HANDOFF.md` `M`
  triggers the "Stashing unstaged files" warning — harmless).
- **PR #83 is open and unmerged** — no review comments yet; it's the in-flight item.
