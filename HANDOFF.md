# HANDOFF — 2026-08-04 (PST), covering work done 2026-07-27

**Agent-instruction hygiene session.** Picked up from the 2026-07-22 handoff (which was already
5 days stale on arrival), ran a `dv:review-claudemd` pass over recent sessions, and landed two
PRs of global-CLAUDE.md corrections. Also diagnosed and fixed a terminal-rendering complaint that
surfaced a real repo gap: Otty's config is not tracked by this repo at all. Master is green and
clean, no open PRs.

Note on dating: all commits and the Otty change happened **2026-07-27 (PDT)**; this handoff was
written 2026-08-04 after the window sat idle. Nothing changed in between — `git status` is clean
and `master` matches `origin/master`.

## What We Built

- **PR #122 (`519fd3f`) — stale command names + realtime-fact scope gap.** Two fixes in
  `claude/CLAUDE.md`:
  - `/verify-cite` → `dv:cite`, `/reddit` → `dv:reddit`, `/pickup` → `dv:pickup`. These predated
    the dv-plugin consolidation; `/verify-cite` no longer resolves at all (it now sits in
    `~/.claude/.deprecated-skills/verify-cite`, and there is no `~/.claude/commands/` or
    `claude/commands/` directory). Renames verified against the live 9-skill inventory. `/ops`
    was deliberately left alone — it is a Proof API endpoint path, not a command.
  - New **"A coding task does not exempt a realtime fact"** paragraph in the Web Tool Ladder.
    Closes a gap a prior session fell into: a runner's default model ID was declared stale and
    bumped to a "current" one purely from training data, then committed. Model IDs, package
    versions, API endpoints, pricing, and deprecation status are now explicitly realtime facts
    even mid-coding-task — especially when the value is about to be committed and will fail
    silently later. Routes Anthropic model/pricing questions to the `claude-api` skill.
- **PR #123 (`d81a66f`) — 5 review-claudemd findings** (David-approved), all in `claude/CLAUDE.md`:
  - **Code Review** — `dv:gauntlet` supersedes another project's vault/SOP `codex exec review` or
    Claude↔Codex loop, and holds under `/effort ultracode` and dynamic workflow orchestration.
    Explicit stop-and-invoke trigger on "fan out reviewers" / "spin up a skeptic panel."
  - **Narration** — any `"Let me …"` opener that narrates the next action is banned; scope now
    covers *mid-task* tool-call narration, not just final prose. Background-task status lines are
    still fine.
  - **New "Durable Rules vs Handoff Notes" section** — a durable rule discovered mid-session lands
    in `AGENTS.md`/`CLAUDE.md`/`docs/solutions/` **at discovery**, not parked only in HANDOFF.
    Rationale: `dv:handoff` overwrites wholesale, so a rule living only here is one handoff from
    being lost.
  - **Web Tool Ladder** — machine-readable JSON/registry endpoints (npm, GitHub API, crates.io,
    PyPI) stay at tier 1 even for "current version" facts. And on a failed primary-source fetch,
    escalate tier 1 → tier 2 or decline — never fall back to an untagged secondary source.
  - **Proof exemption list** — names `docs/plans/` + `docs/brainstorms/` alongside
    `docs/solutions/` as one in-repo CE set, with the `ce-proof` carve-out spelled out.
- **Otty ligature fix (machine-local, untracked).** Diagnosed the "weird artifact replacing `&&`"
  as a font ligature, not corruption: `~/.config/otty/config.toml` had `font-ligatures` at its
  `dlig` default (discretionary ligatures) with `font-family = JetBrains Mono`, which collapses
  `&&`, `||`, and `--` into merged glyphs. Set `font-ligatures = "calt"` via
  `otty config set font-ligatures calt --reload` — standard code ligatures (`->`, `=>`, `!=`,
  `<=`) kept, discretionary set off. Diff was a clean two-line append; nothing else reformatted.

## Decisions Made

- **`calt` over full-off.** Kept standard code ligatures rather than killing all of them
  (`font-ligatures = ""`), since only the `dlig` set was producing the unreadable `&&`/`||`/`--`
  substitutions. Revert paths: `otty config unset font-ligatures --reload` restores `dlig`;
  `otty config set font-ligatures "" --reload` disables everything.
- **`/ops` left as-is in CLAUDE.md** — it reads like a slash command but is a Proof API endpoint
  path. Do not "fix" it in a future rename pass.
- **Otty config tracking not acted on unilaterally** — flagged as a gap (see What's Next) rather
  than wiring up an `otty/` dir + Dotbot link without approval.

## What Didn't Work

- **`otty config set --transient` is advertised but not implemented** — returns
  `error: Transient config not yet implemented`. The `--help` output lists the flag, so this is an
  Otty bug, not a usage error. There is no way to preview a config change without persisting it;
  back up `config.toml` first and use `--reload`, then revert if unwanted.
- **`stat -f "%Sm"` does not work as expected in this shell** — `stat` resolves to GNU coreutils,
  where `-f` means "filesystem info," so it prints filesystem stats instead of a formatted mtime.
  Use `/usr/bin/stat -f "%Sm" <file>` for the BSD behavior.
- **`fontTools` is not installed**, so the JetBrains Mono GSUB feature tables could not be
  inspected to confirm exactly which tag carries the `&&` substitution. The diagnosis rests on the
  config value + observed rendering, which was sufficient — the `calt` change confirmed it.

## What's Next

1. **Decide whether Otty config joins the repo.** `~/.config/otty/config.toml` is untracked — no
   `otty/` dir, no `dotbot-conf/` link. Theme (`com.googlecode.iterm2` / Nord), the full custom
   palette, `copy-on-select`, `clipboard-trim-trailing-spaces`, `macos-option-as-alt`,
   `cursor-animation`, and the new `font-ligatures` setting are all machine-local and lost on a
   fresh install. Given this repo is the single source of truth for two Macs, that is a real gap.
   Either open a board ticket or wire it up (`otty/config.toml` + a `base.yaml` link). Watch out:
   `~/.config/otty/` also holds `themes/`, `recipes/`, and `fonts/` — decide the tracking boundary
   before symlinking the whole directory.
2. **Issue #101** — `helpers/install_omz.sh` staging-swap redesign for full crash-atomicity
   (P0-1 follow-up). Install into a unique staging sibling, validate completeness, atomically
   rename into place; ends the recurring "quarantine→reinstall isn't SIGKILL-atomic" finding
   class. Explicitly non-urgent — current implementation is production-grade for a serially
   invoked installer.
3. Otherwise the board is the source of work:
   https://github.com/users/villavicencio/projects/2

## Gotchas & Watch-outs (durable)

- **Do NOT conform/edit the Otty `# >>>`…`# <<<` block in `zsh/zshrc`** (tool-managed; #97→#99).
- **`zsh/zshenv` must stay POSIX-safe** — `.`-sourced by `dash`/`bash` during `./install`;
  zsh-only syntax is a fatal "bad substitution" there.
- **`~/.claude/settings.json` on this Mac is a decoupled regular file with machine-local Otty
  hooks — never symlink the repo baseline over it.** The tracked `claude/settings.json` is the
  clean shared baseline for *fresh* machines only. A Bash-level rewrite of the live file is
  blocked by the permission classifier; the Edit tool (via the `update-config` skill) is the
  sanctioned path.
- **`claude/CLAUDE.md` is symlinked to `~/.claude/CLAUDE.md`** — edits from any session write back
  through into this repo. An `M` on that file is real intentional content, not harness noise;
  diff and commit it.
- **nvim + iTerm write back into tracked files at runtime** (`:Lazy update` → `lazy-lock.json`;
  NvChad theme picker `<leader>th` → `nvim/lua/chadrc.lua`) — expected churn now the symlink is
  live. `nvim/README.md` has the `skip-worktree` tip for theme flips.
- **Install path is layered** (`dotbot-conf/base.yaml` → platform layer); `./install --dry-run`
  must stay mutation-free — verify with the recipe in `CLAUDE.md`/`AGENTS.md` after a Dotbot bump.
- **Verify tooling:** `dot doctor` (read-only health), `dot check` (mirrors CI static checks),
  `dot bench` (startup vs 300 ms). `AGENTS.md` is the tool-neutral repo brief.
- **Adversarial code review routes through `dv:gauntlet`** — bare for the full autonomous
  find→refute→fix→commit loop on your own branch, `report` for a single read-only round. The skill
  owns rounds, budgets, and stop rules; do not hand-roll a `codex exec review` loop or re-derive
  the procedure per project. (Supersedes the old "Codex review gate: launch on staged-uncommitted
  changes" note carried in prior handoffs.)
- **Otty CLI quirk:** `otty config set --transient` is a no-op that errors out. Any config
  experiment persists to disk — back up `~/.config/otty/config.toml` first.

## External items (carried, unchanged from 2026-07-07)

Foreman naming, domain buys, Ship Sigma calculator, Dec 11 redirect-flip calendar event.
