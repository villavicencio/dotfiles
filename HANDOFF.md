# HANDOFF — 2026-06-05 (midday PDT)

Short same-day follow-on to the morning recovery session. Confirmed the
post-Pearcleaner plugin tree rebuilt on restart, committed the leftover
machine-generated settings flags (#92), diagnosed and fixed a non-obvious
plugin **install-registry** split state left behind by the rebuild, and
documented that gotcha in `docs/solutions/`. Board empty; working tree clean.

## What We Built
- **#92** `chore` — recorded the `"autoUpdate": true` flags Claude Code wrote onto
  two marketplace declarations during the plugin rebuild. Synced repo → live state:
  `claude/settings.json` (compound-engineering-plugin) and `.claude/settings.json`
  (villavicencio/skills). Squash-merged, branch deleted, master clean.
- **Fixed the `/plugin` "Update now → Plugin not installed" error.** Root cause:
  the post-Pearcleaner restart rebuilt `~/.claude/plugins/` from `settings.json`,
  which restored the marketplace clones, cache, and `enabledPlugins` (so plugins
  *loaded* — agents/skills present, UI showed "Enabled"), but only re-registered
  `dv` in `installed_plugins.json` (the *install registry* that drives
  Update/Uninstall). `compound-engineering` and `frontend-design` were
  **enabled-but-not-installed** → lifecycle ops failed with "not installed."
  Fix: backfilled via the CLI without disturbing the loaded plugins —
  `claude plugin install compound-engineering@compound-engineering-plugin` and
  `claude plugin install frontend-design@claude-plugins-official`.
  `claude plugin list` now shows all three installed + enabled.
- **`a54a8a1` `docs`** — wrote
  `docs/solutions/code-quality/claude-code-plugin-registry-desync-after-plugins-dir-wipe.md`
  capturing the two-registry desync: on-disk diagnosis commands, the
  `claude plugin install` fix, the `version: "unknown"` + duplicate-cache-dir
  caveats, and a verified `comm`-based reconcile snippet that lists all
  enabled-but-unregistered plugins in one pass (tested — runs clean, returns
  empty in the fixed state). Committed direct to master per the docs carve-out.

## Decisions Made
- Used `claude plugin install` (the supported install flow) to repair the registry
  rather than hand-editing `installed_plugins.json` — guarantees schema-correct
  entries (path, version, gitCommitSha, timestamps).
- Committed the autoUpdate flags via branch+PR (#92) rather than direct-to-master,
  matching the repo default and the #91 settings-sync precedent. They're
  machine-generated but persistent drift, so recording them keeps `git status` clean.
- Filed the new solution doc under `code-quality/` (dateless filename) to sit with
  the existing `claude-code-*` sibling docs, not `cross-machine/` — the reusable
  lesson is a Claude Code plugin-state behavior, independent of the Pearcleaner
  trigger that surfaced it.
- **Pearcleaner replacement: explored, not adopted.** Discussed GUI (AppCleaner,
  Hazel) and CLI (`brew uninstall --cask --zap`, `trash`, `mdfind`) alternatives.
  User closed the thread with "never mind" — no tooling change made. The reframe
  stands if it recurs: the danger was global cache/binary *sweeping* (Lipo, orphan
  hunt), not per-app uninstall; `brew --zap` is the CLI-native, declarative,
  auditable replacement.

## What Didn't Work
- Nothing failed this session. (`Update now` in the `/plugin` UI was the *symptom*
  being fixed, not an approach we tried.)

## What's Next
1. **Board is empty — no open PRs or tickets.** Nothing queued. The plugin-registry
   gotcha that was the prior handoff's optional follow-up is now documented and
   shipped (`a54a8a1`).

## Gotchas & Watch-outs
- **Two plugin registries can desync** — now documented in full at
  `docs/solutions/code-quality/claude-code-plugin-registry-desync-after-plugins-dir-wipe.md`.
  Short version: `enabledPlugins` (settings.json) drives loading;
  `installed_plugins.json` drives Update/Uninstall. A plugin can be
  loaded-and-enabled yet invisible to lifecycle ops. Symptom: "Plugin X is not
  installed" on Update/Uninstall while it clearly works. Fix:
  `claude plugin install X@marketplace`; verify with `claude plugin list`.
- **`frontend-design` registered as version "unknown"** — expected, not a bug.
  Official-marketplace plugins are pinned by commit SHA, not semver. The install
  also created a second cache dir (`.../frontend-design/unknown` alongside the
  pre-existing `435820146b71`); harmless, left in place — do **not** delete cache
  dirs to "tidy up" (that's the class of action that caused the original wipe).
- **settings.json symlink held this session** — the autoUpdate-flag commit went
  through without the symlink re-breaking. Keep watching: Claude Code's atomic
  writes can still replace `~/.claude/settings.json` with a real file (the #91
  failure mode). If `M claude/settings.json` stops reflecting edits, re-sync +
  relink.
- Axiom VPS sync unchanged: `ssh root@openclaw-prod 'sudo -u axiom git -C
  /home/axiom/.dotfiles pull --ff-only'` (statusline / global CLAUDE.md only;
  zsh tooling and plugin state don't apply there).
