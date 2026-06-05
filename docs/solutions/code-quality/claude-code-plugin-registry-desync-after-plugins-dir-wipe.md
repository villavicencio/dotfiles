---
title: "Claude Code plugin Update/Uninstall fails with 'Plugin not installed' after a ~/.claude/plugins wipe — enabled ≠ installed"
date: 2026-06-05
category: code-quality
tags:
  - claude-code
  - plugins
  - settings
  - state-desync
  - recovery
  - pearcleaner
severity: Low
component: "~/.claude/plugins/installed_plugins.json; ~/.claude/settings.json enabledPlugins; claude plugin CLI"
symptoms:
  - "`/plugin` UI shows a plugin as Enabled with all its agents/skills loaded, but 'Update now' fails with: Failed to update: Plugin \"<name>\" is not installed"
  - "'Uninstall' on the same plugin also fails the same way"
  - "`claude plugin list` shows fewer plugins than are actually loaded and enabled in the session"
  - "Happens after `~/.claude/plugins/` was deleted and rebuilt (e.g. a Pearcleaner cache sweep) and Claude Code was restarted"
problem_type: state_desync
module: claude-code-plugins
status: Resolved
---

## Summary

Claude Code tracks plugins in **two independent registries**, and they can desync:

| Registry | File | Drives |
|---|---|---|
| **enabled** | `~/.claude/settings.json` → `enabledPlugins` | *Loading* — what gets mounted at startup (agents, skills, hooks) |
| **installed** | `~/.claude/plugins/installed_plugins.json` | *Lifecycle ops* — Update / Uninstall / `claude plugin list` |

A plugin can be **enabled-but-not-installed**: it loads and runs (agents/skills present, `/plugin` shows "Enabled"), yet every lifecycle operation fails with `Plugin "<name>" is not installed`, because Update/Uninstall look it up in `installed_plugins.json` and find nothing.

The fix is to re-run the supported install flow, which backfills the install registry without disturbing the already-loaded plugin:

```bash
claude plugin install <plugin>@<marketplace>
```

## How we hit it

A Pearcleaner cache sweep on the personal Mac deleted `~/.claude/plugins/` entirely (cache, marketplace clones, `installed_plugins.json`, `known_marketplaces.json`, `plugin-catalog-cache.json`). On the next Claude Code restart the tree rebuilt from `settings.json`:

- `known_marketplaces.json` — restored (all 5 marketplaces re-registered)
- marketplace clones + `cache/` — re-fetched (e.g. `compound-engineering` 3.11.1 fully populated)
- `enabledPlugins` — survived in `settings.json`, so every enabled plugin *loaded* normally
- `installed_plugins.json` — rebuilt with **only `dv`**, the one plugin explicitly reinstalled through `/plugin install` that session

Result: `compound-engineering` and `frontend-design` were enabled (loading fine, UI green) but absent from the install registry. Clicking **Update now** in `/plugin` returned `Failed to update: Plugin "compound-engineering" is not installed`.

## Investigation

The two-registry split is visible directly on disk.

**Install registry — only one entry, but three plugins were loaded:**
```bash
cat ~/.claude/plugins/installed_plugins.json
# "plugins": { "dv@villavicencio-skills": [ ... ] }   ← only dv
```

**Enabled set — all three present (this is what made them load):**
```bash
python3 -c 'import json;print(json.load(open("'"$HOME"'/.claude/settings.json"))["enabledPlugins"])'
# {'frontend-design@claude-plugins-official': True,
#  'compound-engineering@compound-engineering-plugin': True,
#  'dv@villavicencio-skills': True, 'vercel@...': False}
```

**Cache — the plugin is physically present and healthy:**
```bash
ls ~/.claude/plugins/cache/compound-engineering-plugin/compound-engineering/
# 3.11.1   (agents/ + skills/ all there)
```

**CLI agrees with the install registry, not the loaded session:**
```bash
claude plugin list
# only dv@villavicencio-skills
```

So: enabled + cached + loaded, but not in the install registry → lifecycle ops blind to it.

## Root cause

The restart-driven rebuild restores *loading state* (`enabledPlugins` + marketplace clones + cache) but does **not** reconstruct `installed_plugins.json` for plugins it merely loads. Only plugins put through the install flow that session get an install-registry entry. Enabled-but-unregistered plugins therefore work in every way except Update/Uninstall.

## Working solution

Re-run the install flow for each enabled-but-unregistered plugin. It detects the existing cache, writes the missing `installed_plugins.json` entry, and leaves the loaded plugin untouched:

```bash
claude plugin install compound-engineering@compound-engineering-plugin   # ✔ 3.11.1
claude plugin install frontend-design@claude-plugins-official            # ✔
```

Verify:
```bash
claude plugin list   # all three now installed + enabled
```

**Do not** hand-edit `installed_plugins.json` — let the CLI write schema-correct entries (`installPath`, `version`, `gitCommitSha`, timestamps). For a plugin with a real semver the entry is exact; official-marketplace plugins pinned by commit SHA register as `version: "unknown"` (see below).

To recover *all* enabled-but-unregistered plugins in one pass:
```bash
# enabled (settings.json) minus installed (installed_plugins.json) = needs backfill
comm -23 \
  <(python3 -c 'import json;[print(k) for k,v in json.load(open("'"$HOME"'/.claude/settings.json")).get("enabledPlugins",{}).items() if v]' | sort) \
  <(python3 -c 'import json;[print(k) for k in json.load(open("'"$HOME"'/.claude/plugins/installed_plugins.json"))["plugins"]]' | sort) \
| while read p; do echo "claude plugin install $p"; done
# review the printed commands, then run them
```

## Gotchas

- **`frontend-design` registers as `version: "unknown"`** — expected, not a bug. Official-marketplace plugins are pinned by commit SHA, not semver. The install also created a second cache dir (`.../frontend-design/unknown` alongside the pre-existing `.../435820146b71`). It's harmless; **leave it.** Deleting cache dirs to "tidy up" is the exact class of action (Pearcleaner cache sweep) that caused the original wipe.
- **Restart is the trigger, not the cure.** After a `~/.claude/plugins/` wipe, restarting Claude Code rebuilds *loading* and makes everything look fine — masking the fact that the install registry is still incomplete. The desync only surfaces the first time you try to Update or Uninstall.
- **Symptom is misleading.** "Plugin not installed" while the plugin's skills are demonstrably working reads like a bug in the plugin or marketplace. It isn't — it's a registry-scope mismatch.

## Prevention

After any event that touches `~/.claude/plugins/` (cache cleaner, manual deletion, restore-from-backup), don't trust the green "Enabled" state in `/plugin`. Reconcile the two registries explicitly:

```bash
claude plugin list   # compare against settings.json enabledPlugins; backfill any gaps
```

This is the missing step that the prior "restart rebuilds the tree" recovery note assumed but didn't cover: restart fixes loading; only `claude plugin install` fixes the install registry.

## Related documentation

- `docs/solutions/cross-machine/corporate-mac-ssl-and-tooling-setup.md` — other Claude Code environment recovery on a second machine.
- `docs/solutions/code-quality/claude-code-telemetry-flag-does-not-affect-cache-ttl.md` — sibling case of a Claude Code settings.json assumption corrected by inspecting on-disk state rather than trusting the UI/docs.
- `docs/solutions/code-quality/claude-code-hook-stdio-detach.md` — Claude Code settings.json execution model; relevant when touching `settings.json`.
- CLAUDE.md "post-Pearcleaner recovery" history (PR #91) — the settings.json sync that made `enabledPlugins` the load-bearing recovery map this doc depends on.

## References

- `claude plugin --help` — `install|i`, `list`, `uninstall|remove`, `update`, `marketplace` subcommands (verified on Claude Code 2.1.x).
- Registry files: `~/.claude/plugins/installed_plugins.json` (install registry, `version: 2` schema), `~/.claude/plugins/known_marketplaces.json` (marketplace registry), `~/.claude/settings.json` → `enabledPlugins` (enable/load registry).
