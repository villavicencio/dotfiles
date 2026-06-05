# HANDOFF — 2026-06-05 (morning PDT)

VPS ops + local system-recovery session. Merged the two pending PRs (#88 delta,
#89 atuin) plus a recovery PR (#91), **closing the board**. The back half was
recovering from a **Pearcleaner Lipo incident** on the personal Mac that deleted
Oh My Zsh's plugin dir and the *entire* Claude Code plugin tree.

> ⚠️ **READ FIRST:** Claude Code's plugin directory was wiped. After restarting
> Claude Code it should rebuild — verify per **What's Next #1** before assuming
> skills/plugins work.

## What We Did

**Merged (board now empty — no open PRs or tickets):**
- **#91** `chore` — post-Pearcleaner recovery: synced `~/.claude/settings.json`
  (it had drifted to a real file, *newer* than the repo) back into the repo and
  restored the tracked symlink; added `lazygit` to the Brewfile.
- **#88** `feat(git)` — delta as the diff/show pager (`core.pager = vim -` kept
  for log/etc.). Live now: delta 0.19.2, `pager.diff = delta`.
- **#89** `feat(zsh)` — atuin `^R` history + hosted sync; **closed #82**. Live
  now: atuin 18.16.1, registered as `villavicencio`. `exec zsh` loads `^R` in
  shells started before the merge.

**VPS (Axiom / `openclaw-prod`) fixes:**
- tmux-resurrect `save.sh returned 127` — plugins were never installed (only tpm
  was cloned). Ran `~/.config/tmux/plugins/tpm/bin/install_plugins` → resurrect /
  continuum / sensible / focus-events installed; `save.sh` exits 0 and writes
  state. `@continuum-restore on` will now restore on reboot.
- Reinstalled the Claude Code **native** binary (user accidentally uninstalled it):
  `curl -fsSL https://claude.ai/install.sh | bash` **as `axiom`, not root** →
  v2.1.153 at `~/.local/bin/claude`. `~/.claude` config + `~/.claude.json` auth
  were preserved → no re-login.
- dv plugin install failed on VPS — marketplace `villavicencio-skills` was
  registered but its clone was missing. `git clone https://github.com/villavicencio/skills`
  into `~/.claude/plugins/marketplaces/villavicencio-skills` (shallow); dv then
  installed.

**Local Pearcleaner Lipo recovery (personal Mac):**
- Lipo invalidated app code signatures (apps reinstalled by user) and deleted
  files. Full health sweep result: dotfiles repo clean, **all CLI tooling execs
  (no binary corruption)**, `brew bundle check` satisfied (**zero brew packages
  removed**), 16/17 declared symlinks intact.
- **OMZ `~/.oh-my-zsh/plugins/` wiped (881 git-tracked files)** → restored offline:
  `git -C ~/.oh-my-zsh checkout -- plugins`. 357 built-ins back; `zsh -i` clean.
- **`~/.claude/plugins/` deleted ENTIRELY** (cache, marketplace clones,
  `installed_plugins.json`, `known_marketplaces.json`, `plugin-catalog-cache.json`).
  Caught when `dv:handoff` failed mid-session. Rest of `~/.claude/` (commands,
  hooks, skills, settings.json, CLAUDE.md, statusline) survived.

## Decisions Made
- Pearcleaner: **not** writing a `docs/solutions/` entry (user won't repeat the
  action). `fixmouse` keybinding **dropped**. tmux right-pane text-selection quirk
  **self-resolved** after a tmux restart.
- The #91 settings.json sync turned out load-bearing — it's the declarative
  source that drives plugin re-acquisition after the cache wipe (see below).

## What's Next
1. **Restore Claude Code plugins — RESTART REQUIRED.** `~/.claude/plugins/` is
   gone, but `~/.claude/settings.json` still declares the marketplaces + enabled
   plugins, so **restarting Claude Code rebuilds the tree from settings.json**
   (same path a fresh machine takes). After restart, verify:
   - `ls ~/.claude/plugins/` is repopulated (cache/ + marketplaces/ back), and
   - a dv skill works (e.g. `/dv:pickup`).
   - If it does **not** auto-rebuild, re-add manually via `/plugin` →
     *Marketplaces*. Declared in settings.json:
     - **Enabled plugins:** `frontend-design@claude-plugins-official`,
       `compound-engineering@compound-engineering-plugin`, `dv@villavicencio-skills`
     - **Marketplaces:** `anthropics/claude-code`,
       `EveryInc/compound-engineering-plugin`, `anthropics/claude-plugins-official`,
       `villavicencio/skills`, `villavicencio/skills-private` *(private — needs gh
       auth; you're logged in as `villavicencio`)*
2. Board is otherwise empty.

## Gotchas & Watch-outs
- **Pearcleaner Lipo is destructive well beyond binary-thinning** — it deleted
  `~/.oh-my-zsh/plugins/` *and* all of `~/.claude/plugins/`. Anything with `cache`
  in the path is a target, and there is no pre-deletion preview (Pearcleaner FR
  #489). User does not intend to run it again.
- **`~/.claude/settings.json` can re-break its symlink:** Claude Code's atomic
  writes replace the tracked symlink with a real file (happened this session). If
  `M claude/settings.json` stops reflecting local edits, re-sync local→repo +
  relink (the #91 procedure). It is the recovery map for plugins — keep the repo
  copy current.
- **VPS dv marketplace clone is shallow** (`--depth 1`, autoUpdate on). If an
  auto-update ever hiccups: `git -C ~/.claude/plugins/marketplaces/villavicencio-skills fetch --unshallow`.
- **atuin = personal Mac only.** Work Mac stays unregistered so corporate history
  never leaves the device.
- Axiom VPS sync (statusline / global CLAUDE.md only):
  `ssh root@openclaw-prod 'sudo -u axiom git -C /home/axiom/.dotfiles pull --ff-only'`.
  zsh tooling (eza/zoxide/atuin) does **not** apply there — axiom's shell is bash.
