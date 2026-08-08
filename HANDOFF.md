# HANDOFF — 2026-08-07 (PDT), midday

**Short continuation session, not a new day.** Picked up ~33 minutes after the previous handoff
was written (12:02 → 12:35 PDT) — a context clear for hygiene, not an overnight gap. David ran
`topgrade` from `!` mode; it reported one failed step, which was diagnosed as benign. The only
code change was committing the `claude/CLAUDE.md` write-back that a *different* session had
produced. One PR merged (#133), master clean, no open PRs.

## What We Built

- **PR #133 (`73354d9`) — Web Tool Ladder tier 2 repointed Browserbase → Obscura.** The content
  was authored by another session writing through the `~/.claude/CLAUDE.md` symlink; this session
  found it as an uncommitted ` M claude/CLAUDE.md`, branched, and shipped it. +40/−6. Substance:
  - Tier 2 is now **Obscura**, which ships as the MCP server named **`browse-gateway`**. The brand
    name appears nowhere on disk — no binary, no skill, no config string — so grepping for
    "obscura" wrongly reads as "not installed." Load path recorded:
    `ToolSearch("select:mcp__browse-gateway__retrieve")`.
  - Tool split recorded: `retrieve` for **reading** a page (stealth browser, clears Cloudflare/
    CAPTCHA, `forceProxy: true` for known-hostile hosts); `browser_*` for **stateful interaction**
    only. A warm logged-in session pins to one owner host.
  - **Availability is per-project, not global**: configured only in `~/Projects/agents` and
    `/Volumes/1TB Media/Erato`. Not in this repo. The root-level MCP entry is still the retired
    `browserbase` — dead, not a fallback.
  - **Obscura has no search API.** WebSearch stays the only path for *finding* candidate URLs,
    and a SERP snippet is still not a verified fact — fetch with `retrieve` before quoting.
  - Skill inventory: still Browserbase-shaped and unrepointed (`search` — unfixable,
    `company-research`, `event-prospecting`, `ui-test`, `autobrowse`, `safe-browser`,
    `what-antibot`, `agent-browser`); structurally obsolete (`functions`, `cookie-sync`);
    already working (`fetch`, `dv:cite`/`verify-cite`).
- **CI-visibility rule landed durably** in `CLAUDE.md` (Branching & pull requests) and `AGENTS.md`
  — docs-only PRs report "no checks reported" by design. Written at discovery rather than parked
  here, per the global durable-rules-vs-handoff rule.
- **`topgrade` run (David-initiated, no repo changes).** 20 of 21 steps OK. ast-grep
  0.45.0 → 0.45.1, `mac-cleanup-py` freed 1.28 GB, an Ollama model pulled 6.1 GB, Neovim reported
  "Plugins upgraded" but produced **no `lazy-lock.json` churn** this time.

## Decisions Made

- **The `topgrade` "Claude Code Plugins: FAILED" is benign — do not chase it.** The whole step
  failure is one plugin: `erato@villavicencio-skills-private`, registered at **project scope for
  `/Volumes/1TB Media/Erato`**, and that volume is **not mounted**. `claude plugin update
  … --scope project` cannot resolve the project path, so it errors and topgrade marks the step
  FAILED. Ground truth is `~/.claude/plugins/installed_plugins.json` (the entry names both the
  scope and the `projectPath`); `~/.claude.json` only carries `pluginUsage`/`skillUsage`
  telemetry for erato, which is a red herring when grepping.
- **Merged #133 without waiting for CI.** `install-matrix.yml`'s `paths-ignore` covers
  `claude/**/*.md`, so no run was ever going to start. Verified by reading the workflow's `on:`
  block rather than assuming — `mergeStateStatus: CLEAN` was the actual signal.
- **Committed the `claude/CLAUDE.md` write-back rather than reverting or ignoring it.** It is real
  authored content arriving through the symlink, exactly the case the prior handoff's gotcha
  describes.

## What Didn't Work

- **Grepping `~/.claude.json` for the erato install scope is a dead end.** Its `projects` map has
  no plugin-install records; the only `erato` hits are usage telemetry. The install registry is a
  separate file: `~/.claude/plugins/installed_plugins.json`.
- **`stat -f '%Sm' HANDOFF.md` printed filesystem info again** — the carried gotcha below is real
  and was re-hit within a minute of session start. `/usr/bin/stat -f '%Sm'` is the fix.
- **A `python3 - <<'EOF'` heredoc silently produced no output** while inspecting `~/.claude.json`
  (masked by `2>/dev/null || true`). Rewriting it as a real script file in the scratchpad worked
  on the first try. Not proven to be the #131 deadlock, but the same shape the repo already
  banned in `bin/dot` — prefer a script file.

## What's Next

1. **Issue #101** — `helpers/install_omz.sh` staging-swap redesign for full crash-atomicity
   (P0-1 follow-up). Install into a unique staging sibling, validate completeness, atomically
   rename into place. The **only** open issue on the board. Explicitly non-urgent — the current
   implementation is production-grade for a serially invoked installer.
2. **Restart Claude Code to pick up plugin updates.** `topgrade` moved `dv` from **0.2.2 → 0.3.0
   at project scope for this repo** (user scope was already 0.3.0), and refreshed
   `frontend-design` and `skill-creator`. All three printed "Restart to apply changes"; the
   session that ran them is still on the old copies.
3. **Launch Docker Desktop once** (carried, unchanged). Its privileged helpers
   (`com.docker.helper`, `com.docker.socket`, `com.docker.vmnetd`) are still absent from
   `/Library/PrivilegedHelperTools/` — the failed cask upgrade removed them and
   `brew upgrade --cask` does not reinstall them; first app launch does. Low urgency: `colima` is
   the active docker context.
4. **Mount `/Volumes/1TB Media` before the next `topgrade`** if you want the erato plugin update
   to land — otherwise expect the same FAILED line and ignore it.
5. **Consider Touch ID on the work Mac** (carried). Documented in `CLAUDE.md`, applied only to
   personal. Corporate MDM may override `/etc/pam.d/`.
6. Otherwise the board is the source of work:
   https://github.com/users/villavicencio/projects/2

## Gotchas & Watch-outs (durable)

**New this session**

- **`topgrade` marks "Claude Code Plugins: FAILED" whenever a project-scoped plugin's
  `projectPath` is on an unmounted volume.** One plugin fails the whole step. Read the per-plugin
  lines in the output before treating the step as broken, and check
  `~/.claude/plugins/installed_plugins.json` for scope + path.
- **Docs-only PRs legitimately report "no checks reported."** Now documented in `CLAUDE.md` and
  `AGENTS.md`. `install-matrix.yml` sets `paths-ignore: ['docs/**', '**.md', 'claude/**/*.md']`.
  Merge on `mergeStateStatus: CLEAN`.
- **Obscura ≠ any on-disk name.** It is the `browse-gateway` MCP server, and it is **not wired up
  in this repo** — tier 2 of the Web Tool Ladder does not resolve here. Add the server for the
  project or say it isn't available; do not silently drop to WebFetch. Full detail in
  `claude/CLAUDE.md`.

**Carried forward (still true)**

- **`otty/` is copy-seeded — never add a `link:` entry for it.** Rationale in `CLAUDE.md` ("Otty
  config — copy-seeded, never symlinked") and the solutions doc. To record live changes:
  `dot drift`, then `bash helpers/install_otty.sh --capture`. Not `cp` — that destroys the header
  and pastes the cruft.
- **`otty config set --transient` is a no-op that errors out.** Every config experiment persists —
  back up `~/.config/otty/config.toml` first.
- **Do NOT conform/edit the Otty `# >>>`…`# <<<` block in `zsh/zshrc`** (tool-managed; #97→#99).
- **sudo does not work from an agent shell without Touch ID.** Set up and verified on the personal
  Mac. If it regresses, check `/etc/pam.d/sudo_local` exists (444, root) and that `pam_reattach`
  comes *before* `pam_tid`.
- **No heredocs in `bin/dot` — do not inline `bin/lib/*.py` back.** If any bash script here hangs,
  the tell is **a shell process with no children**; `sample <pid>` and look for `heredoc_write`.
  Counter-intuitively **small heredocs are the risky ones** (bash uses a temp file for large ones),
  and the bug does not reproduce from the syntactic pattern in isolation. Two plausible theories
  are wrong: "payload exceeds the pipe buffer" (a 2 KB–253 KB sweep never deadlocks) and
  `net.local.stream.sendspace` (a unix-socket knob, unrelated).
- **`dot doctor` is slow (~30–60 s) but no longer hangs.** Never exercised by CI, which is how a
  12%-failure-rate deadlock survived in a documented verify command.
- **`gh pr merge --delete-branch` silently skips the remote branch if the local delete fails.**
  Verify with `git ls-remote --heads origin <branch>` after merging any PR whose branch is checked
  out somewhere. (Done for #133 — remote branch confirmed gone.)
- **`git branch --merged` is useless here.** Every PR is squash-merged, so merged branches read as
  unmerged. Compare *content* with `git diff master <branch>`.
- **`dot check`'s dotbot-parse step always FAILs inside a git worktree** — worktrees do not
  populate submodules, so `dotbot/bin/dotbot` is absent. Not a regression.
- **`stat -f "%Sm"` prints filesystem info here** — `stat` resolves to GNU coreutils. Use
  `/usr/bin/stat -f "%Sm" <file>` for BSD mtime formatting.
- **`claude/CLAUDE.md` is symlinked to `~/.claude/CLAUDE.md`** — edits from any session, including
  concurrent ones, write back through into this repo. An `M` there is real content; diff and
  commit it. (That is exactly what #133 was.)
- **`~/.claude/settings.json` on this Mac is a decoupled regular file with machine-local Otty
  hooks — never symlink the repo baseline over it.** The tracked `claude/settings.json` is the
  clean shared baseline for *fresh* machines only. The Edit tool (via `update-config`) is the
  sanctioned path; a Bash-level rewrite is blocked by the permission classifier.
- **Claude Code permissions: `permissions.allow` is the allowlist; there is no `allowedTools`
  key.** If a rule appears ignored, check for a resurrected legacy `allowedTools` first — it wins
  silently.
- **nvim + iTerm write back into tracked files at runtime** (`:Lazy update` → `lazy-lock.json`;
  NvChad theme picker `<leader>th` → `nvim/lua/chadrc.lua`). Expected churn — commit it.
  `nvim/README.md` has the `skip-worktree` tip for theme flips.
- **`zsh/zshenv` must stay POSIX-safe** — `.`-sourced by `dash`/`bash` during `./install`;
  zsh-only syntax is a fatal "bad substitution" there.
- **A working `docker` command says nothing about Docker Desktop.** colima is the active context;
  check `docker context ls` before drawing conclusions.
- **`brew postinstall python@3.10` warns and cannot be "fixed" — it is cosmetic.** Exits 0, all
  artifacts present. Stop chasing it.
- **Install path is layered** (`dotbot-conf/base.yaml` → platform layer); `./install --dry-run`
  must stay mutation-free — verify with the recipe in `CLAUDE.md`/`AGENTS.md` after a Dotbot bump.
- **Verify tooling:** `dot doctor` (read-only health, slow), `dot check` (mirrors CI static
  checks), `dot bench` (startup vs 300 ms). `AGENTS.md` is the tool-neutral repo brief.
- **Adversarial code review routes through `dv:gauntlet`** — bare for the full autonomous
  find→refute→fix→commit loop, `report` for a single read-only round. Do not hand-roll a
  `codex exec review` loop or re-derive the procedure per project.

## External items (carried, unchanged from 2026-07-07)

Foreman naming, domain buys, Ship Sigma calculator, Dec 11 redirect-flip calendar event.
