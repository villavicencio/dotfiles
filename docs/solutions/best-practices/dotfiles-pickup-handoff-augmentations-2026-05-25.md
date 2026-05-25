---
title: "Dotfiles-specific augmentations for /pickup and /handoff (after migrating to villavicencio/skills plugin)"
date: 2026-05-25
category: best-practices
tags:
  - claude-code
  - session-management
  - pickup-handoff
  - dotbot
  - symlinks
  - install-conf-yaml
  - compound-learning
severity: Informational
component: "Claude Code skill discovery + dotfiles repo orientation"
symptoms:
  - "Before the migration, this repo carried `.claude/commands/pickup.md` and `.claude/commands/handoff.md` as project-local Claude Code commands. They duplicated the name `/pickup` and `/handoff` with the universal `pickup-handoff` plugin shipped from villavicencio/skills, producing two picker entries that the user had to disambiguate by reading the description."
  - "The project-local versions only existed to add three dotfiles-specific behaviors on top of the generic session-bracket flow. Forking the entire skill to add three checks is duplication."
problem_type: "Skill-vs-knowledge separation — universal action templates (skills) vs project-specific context that augments them (compound learnings)"
module: "Claude Code skill discovery in this repo + agent-discoverable institutional knowledge"
related_solutions: []
---

## Context

After v0.1.0 of `pickup-handoff` shipped via [villavicencio/skills](https://github.com/villavicencio/skills) on 2026-05-25, this repo briefly had two `/pickup` and two `/handoff` entries in Claude Code's picker:

1. The universal plugin (`pickup-handoff@villavicencio-skills v0.1.0`) — session-bracket flow that works in any project.
2. A project-local override at `.claude/commands/{pickup,handoff}.md` — the same generic flow, plus three dotfiles-specific checks layered in.

The override was the wrong tool. Forking a universal skill to add project-specific knowledge couples that knowledge to the skill's release cycle and produces a name conflict for any agent / human navigating the picker.

The cleaner shape: **skills are universal action templates; project-specific augmentations live as docs/solutions/ entries that agents discover via `ce-learnings-researcher` when the project context is relevant.**

The project-local overrides have been deleted. This doc captures the three augmentations that an agent should layer onto the universal `/pickup` or `/handoff` flow when working in *this* repo (or any dotbot-style dotfiles repo).

## Augmentation 1 — Broken symlink scan

**When:** as part of `/pickup`'s context-gathering phase, AND as part of `/handoff`'s "check for issues" phase.

**Why:** dotbot-managed dotfiles work by installing symlinks from `~/<dotfile>` → `<repo>/<source>`. The most common silent failure is a dangling symlink — a source file moved or got renamed (e.g., the `.deprecated` rename pattern in `claude/commands/`), and the symlink target no longer resolves. Discovery globs that match by name (like Claude Code's `commands/*.md`) keep surfacing those dangling links until they're explicitly removed.

**How:**

```bash
find ~ -maxdepth 4 -type l ! -exec test -e {} \; -print 2>/dev/null \
  | grep -v "Library\|node_modules" | head -20
```

If any results: surface them immediately in the orientation output. They are usually the most actionable item — a broken symlink in `~/.claude/commands/`, `~/.config/`, etc. tends to be a higher-priority fix than whatever the user thinks they were about to do.

## Augmentation 2 — `install.conf.yaml` drift detection (dotbot manifest)

**When:** as part of `/handoff`'s context-gathering phase, specifically before deciding "is this session ready to commit?"

**Why:** [dotbot](https://github.com/anishathalye/dotbot)'s `install.conf.yaml` is the source of truth for what gets symlinked on a fresh machine install. If you added a new dotfile and updated its source but forgot to register it in `install.conf.yaml`, the dotfile won't get installed on the next machine. This is a class of mistake that doesn't break the current machine — but breaks all *future* machines silently.

**How:**

```bash
git diff HEAD -- install.conf.yaml 2>/dev/null \
  || echo "(no changes to install.conf.yaml)"
```

If there are uncommitted changes to `install.conf.yaml`, note them in the HANDOFF.md so the next session knows which symlinks are new. If there are *new* dotfiles in the working tree but *no* matching `install.conf.yaml` change, flag that explicitly — it's almost always a missed manifest update.

## Augmentation 3 — Dotfiles-flavored HANDOFF.md template

**When:** when `/handoff` writes the HANDOFF.md in a dotfiles repo.

**Why:** the universal `pickup-handoff` plugin's HANDOFF.md template is oriented around feature/bug work (`What We Built / Decisions Made / What Didn't Work / What's Next / Gotchas`). Dotfiles work is config-shaped, not feature-shaped — the most valuable section is *Why*, because config changes are often "I tried this and it broke X" or "I switched away from tool Y because of Z" reasoning that's hard to reconstruct from a diff alone.

**Template to use instead (or in addition):**

```markdown
# HANDOFF — [YYYY-MM-DD, time of day]

[One-paragraph context: what arc this session was on.]

## What Changed
[Concrete bullet list — which config files, which symlinks, which tools.
"Updated nvim/lua/custom/mappings.lua — added telescope live_grep binding" is good.
"Updated nvim config" is not.]

## Why
[The reasoning behind each change. What was broken, what was annoying, what prompted it.
This is the context that's hardest to reconstruct later — config changes don't carry
their reasoning the way code changes do.]

## install.conf.yaml
[Note any new symlinks added or removed. If nothing changed, say so explicitly.
If you added a dotfile but forgot to register it, this section catches that.]

## What's Next
[Prioritized. Lead with the single most important thing.
Include any tools you evaluated but didn't finish setting up.]

## Gotchas & Watch-outs
[Anything fragile, any workaround in place, anything to test on a fresh machine.
If a symlink was tricky to get right, document it here.]
```

The universal plugin's default template still works; this dotfiles-flavored version layers the `Why` and `install.conf.yaml` sections in for richer cross-machine recoverability.

## Why this is a compound learning, not a skill override

- **Skills are universal action templates.** The plugin's `/pickup` and `/handoff` describe the *action* of orienting / serializing a session — the action is the same in any project.
- **Compound learnings are project context that augments those actions.** "When working in dotfiles, also check broken symlinks" is knowledge, not a different action.
- This separation keeps the plugin's contract clean, avoids picker-name conflicts, and lets these patterns evolve independently of the skill's release cycle. Add another dotfiles-specific pattern next month? Append a section here, no skill version bump needed.

## Discovery contract

Any agent working in this repo that loads `docs/solutions/` (e.g., via `ce-learnings-researcher` or similar) should pick up this doc when reasoning about orientation, handoffs, broken symlinks, or `install.conf.yaml`. If the agent invokes `/pickup` or `/handoff` from the universal plugin, it should layer in the three augmentations above before producing its output.
