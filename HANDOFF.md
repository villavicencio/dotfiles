# HANDOFF — 2026-05-30 (PDT)

Two-track session off a cold `/pickup`. Track 1 (the bulk): bootstrapped a brand-new project
— **ibmcconstruction.com**, the site for the user's general contractor (IBMC Construction),
migrating Wix → Next.js + Sanity + Vercel and framed as instance #1 of an agent-operable
SMB-site platform. That work lives in its **own repo** (`~/Projects/ibmcconstruction.com`,
private), parked at context-docs stage. Track 2 (dotfiles): enhanced the Claude Code
statusline to show the `/effort` level, accent the model descriptor, and link the branch
name to GitHub. Closed by reconciling the project board. Tree clean, everything pushed.

## What We Built

**Dotfiles (this repo):**
- **`a621a85` — `docs(claude): add narration & verbosity guidance`.** Added the "Narration &
  Verbosity" section to `claude/CLAUDE.md` (cut-filler / no-preamble rules). This was the
  uncommitted symlink-writeback loose end flagged at `/pickup`.
- **`249a624` — `feat(statusline): effort level, accented descriptor, clickable branch`.**
  Three changes to `claude/statusline-command.sh`:
  - Reads `.effort.level` from the statusline JSON and injects it into the model's paren
    group → `Opus 4.8 (1M context, xhigh)`, the effort word in **bold violet**
    (`38;2;165;110;255`). Bare model name when effort is absent (no empty parens).
  - The parenthetical descriptor ("1M context") now renders in **soft gold**
    (`38;2;205;170;100`). Both accent colors are defined as `effort_color` / `descriptor_color`
    vars near the top for easy tweaking.
  - Branch name wrapped in an **OSC 8 hyperlink** to its GitHub branch
    (`/tree/<branch>`). URL parsed from `origin` offline (handles scp/https/ssh + SSH host
    aliases like `github-work`, strips embedded creds, GitHub-only). BEL-terminated.
- **Project board #2:** moved stale card **#42** (sync-vps tailnet ACL) from *In Progress* →
  *Done*. Underlying issue was already CLOSED (2026-04-20). Board now 28 Done, **0 open issues**
  on either repo.

**IBMC Construction (separate repo — `github.com/villavicencio/ibmcconstruction.com`, private):**
- **`2279ac5`** — scaffold: `CLAUDE.md` (`@AGENTS.md` + forge key `ibmc-construction`),
  `AGENTS.md` (business ground truth, platform posture, stack, IA, Sanity content model,
  agent-native requirements, build phases), `docs/design/design-brief.md` (seed for
  claude.ai/design), `docs/reference/*.png` (current Wix-site screenshots).
- **`28d7967`** — decoupled from `davidandbrittanie.com`: inlined the Next-16 + Sanity stack
  gotchas AGENTS.md previously told the agent to read from d&b, removed all cross-repo
  pointers. Repo is now fully self-contained (no `--add-dir` needed).

## Decisions Made

- **Statusline effort source = live `.effort.level`** from the statusline JSON, not
  `settings.json`'s `effortLevel` default — so it tracks mid-session `/effort` changes.
  Confirmed against captured live JSON (field documented at code.claude.com/docs/en/statusline.md).
- **Solid violet for effort, gold for descriptor.** First shipped a per-char rainbow; user
  found it distracting → replaced with a single solid color. See *What Didn't Work*.
- **iTerm link-underline: explicitly DROPPED.** The underline is iTerm2's link decoration,
  not script-controllable via SGR — governed by the advanced setting `underlineHyperlinks`
  (default YES). User chose to leave it on rather than change the iTerm pref.
- **IBMC architecture calls:** stay on **Sanity** (agent-drivable content API = the platform's
  whole point); build a **single clean site with platform seams** (content-in-Sanity +
  design-tokens), NOT multi-tenant now — defer until client #2 is real; **evolve the brand**
  (keep/refine the logo, kill the rest); design owned in **claude.ai/design**, handed to code
  as a token set.

## What Didn't Work

- **Rainbow per-character effort coloring** — implemented correctly (truecolor per-char cycle)
  but the user found it distracting. Replaced with solid violet. Don't re-propose rainbow.
- **Suppressing the OSC 8 underline from the script** — not possible. It's iTerm2's link
  affordance; only the iTerm advanced setting `underlineHyperlinks=NO` disables it (and even
  then Cmd-hover still underlines, per iTerm gitlab #10584). Ruled out a script-side fix.
- **`browse` CLI via the Bash tool** — the zsh function shim calls `_load_nvm`, which doesn't
  exist in the Bash tool's non-interactive shell (`command not found: _load_nvm`). Had to
  invoke the real binary directly: prepend `~/.config/nvm/versions/node/v24.13.0/bin` to PATH.
  Remember this for any future browser-skill use from the Bash tool here.

## What's Next

- **Dotfiles: nothing pending.** Tree clean, both commits pushed to `master`, board reconciled.
- **IBMC (user-side, genuinely external — why it's parked):**
  1. Paste `docs/design/design-brief.md` into a new **claude.ai/design** project; add
     inspiration links.
  2. Get the **logo source file** from Chris (Wix logo is obfuscated; we only have screenshots).
  3. When design firms up: `cd ~/Projects/ibmcconstruction.com && claude` → "Read the design
     brief and AGENTS.md, then start phase 1" (scaffold Next 16 + Sanity + Tailwind v4). That
     repo's CC is self-contained — **no `--add-dir`** needed; it loads CLAUDE.md→AGENTS.md
     automatically and reads the design brief by path.

## Gotchas & Watch-outs

- **OSC 8 branch link clickability depends on Claude Code + tmux.** User confirmed it IS
  clickable in their iTerm2 + tmux next-3.7. Upstream issues (#27047/#23438) make it
  non-clickable in some tmux setups — degrades to plain (non-clickable) text, not garbled.
  To kill the linking entirely, clear `branch_url` in `claude/statusline-command.sh`.
- **Statusline stays POSIX/dash-safe** (octal escapes only, BEL-terminated OSC 8). Verified
  under both `sh` and `dash`. Re-check on Axiom if a Linux dotfiles target ever revives.
- **iTerm2 prefs load from the repo folder** (`LoadPrefsFromCustomFolder=1`,
  `PrefsCustomFolder=…/dotfiles/iterm`); UI changes flush to `iterm/com.googlecode.iterm2.plist`
  on iTerm quit. The `underlineHyperlinks` setting was NOT changed this session.
- **IBMC ≠ davidandbrittanie.com.** Intentionally decoupled — do not re-introduce cross-repo
  references; the IBMC AGENTS.md is the single source for its stack knowledge.
- **The IBMC arc is a separate repo.** Its HANDOFF/context lives there, not here. This dotfiles
  HANDOFF only tracks the statusline + board work; the IBMC bullets are pointers.
