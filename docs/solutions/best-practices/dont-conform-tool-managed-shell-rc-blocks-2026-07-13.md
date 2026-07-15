---
title: "Don't conform tool-managed shell-rc blocks — the tool re-adds them (Otty, conda, nvm)"
date: 2026-07-13
category: best-practices
tags:
  - zshrc
  - shell-integration
  - dotbot
  - symlink
  - otty
  - installer-blocks
  - idempotency-markers
severity: Low
component: "zsh/zshrc — installer-appended integration blocks (e.g. Otty's `# >>>`/`# <<<` block)"
symptoms:
  - "An integration block you cleaned up/rewrote reappears in `zsh/zshrc` on its own"
  - "`zsh/zshrc` keeps going dirty in `git status` after a fresh shell launch, with a duplicate integration block"
  - "Two copies of the same tool's integration (one hand-edited, one with `# >>>`/`# <<<` markers)"
problem_type: "Rewriting a tool-managed rc block defeats the tool's marker-based idempotency check, so the tool re-appends a fresh copy"
module: "zsh config / install pipeline"
related_solutions:
  - "docs/solutions/cross-machine/adoptopenjdk-dead-tap-fails-brew-bundle-2026-07-13.md — same-session CI-rot cleanup"
  - "docs/solutions/cross-machine/brew-bundle-parallel-cellar-lock-race-macos-runner-2026-07-13.md — same-session CI-rot cleanup"
  - "docs/solutions/code-quality/brew-shellenv-clobbers-path-via-path-helper.md — another zshrc-block gotcha"
---

## TL;DR

Some tools (terminal emulators like **Otty**, and package/env managers like **conda**, **nvm**,
**rbenv**) append a **markered block** to your shell rc — `# >>> otty shell integration >>>` … `# <<< … <<<`.
Those markers are the tool's **idempotency check**: on launch it greps the rc for its markers and,
if it can't find them, appends a fresh block. So if you "clean up" the block to match repo idiom
(collapse it to a one-liner, drop the markers), the tool concludes its integration isn't installed
and **re-adds it** — leaving a duplicate. Because `zsh/zshrc` is **Dotbot-symlinked to the live
config**, that re-add lands straight in the repo working tree, so the tree keeps going dirty.

**Rule:** leave tool-managed markered blocks **verbatim**. The repo's one-line
`[[ … ]] && source …` idiom is only for **hand-managed** integrations (gcloud, openclaw, bun) that
no tool rewrites.

## Symptom

`zsh/zshrc` went dirty on its own after a fresh shell, showing a duplicate — one hand-conformed
line plus a re-added markered block:

```zsh
# Otty shell integration (optional; inert unless launched by Otty)   ← the conformed one-liner
[[ -n "$OTTY_SHELL_INTEGRATION" && -r … ]] && source …

# >>> otty shell integration >>>                                     ← Otty re-added this
if [ -n "$OTTY_SHELL_INTEGRATION" ] && [ -r … ]; then
  . …
fi
# <<< otty shell integration <<<
```

Both blocks are guarded and inert off-Otty, so nothing *breaks* — but the working tree won't stay
clean, and inside Otty the integration sources twice.

## Root cause

**Marker comments are load-bearing, not decoration.** A tool that self-installs into your rc needs
a way to answer "have I already added my block?" without parsing shell semantics. The cheap answer
is a sentinel: wrap the block in unique marker comments and grep for them. Remove or rename the
markers and the check fails → the tool treats the rc as un-integrated and re-appends.

This is the same mechanism behind conda's `# >>> conda initialize >>>`, nvm's block, etc. It looks
like inert boilerplate; it's actually the tool's install-state flag.

**Dotbot symlink amplifies it.** `zsh/zshrc` is symlinked into the live config, so the tool isn't
writing to some throwaway `~/.zshrc` — it's writing into the tracked repo file. Every re-add is an
uncommitted change staring back at you in `git status`.

## What happened here (Otty, #97 → #99)

1. **#97** conformed the Otty installer block to the repo's one-line `[[ … ]] && source …` idiom
   and dropped the `# >>>`/`# <<<` markers — reasonable-looking, matched the gcloud/openclaw lines
   right above it.
2. Within one session of #97 merging, Otty launched a new shell, didn't find its markers, and
   **re-appended a fresh markered block** → duplicate in the working tree.
3. **#99** reverted to Otty's **verbatim** markered block. Otty now matches its own markers on
   launch and stops re-adding. Working tree stays clean.

## The rule / fix

**Classify the block before touching it:**

| Block kind | Who rewrites it | What to do |
|---|---|---|
| **Tool-managed** (Otty, conda, nvm, rbenv, VS Code, etc. — has `# >>>`/`# <<<` or "Added by X" markers) | the tool, on launch/update | **Leave verbatim.** Conforming it just starts a fight you lose every shell launch. |
| **Hand-managed** (gcloud path.inc source, openclaw completion, bun completion) | nobody — you added it once | Conform freely to repo idiom; nothing re-adds it. |

The tell: **does an installed tool actively re-emit this block?** If a live app/CLI owns it via
markers, it's tool-managed — hands off. If you pasted it once and no process regenerates it, it's
yours to shape.

If a duplicate ever appears anyway (e.g. after a tool update changes its marker format), keep the
**markered** copy and delete the extra — the markered one is what the tool will keep managing.

## Sites

- `zsh/zshrc` — the Otty `# >>> otty shell integration >>>` … `# <<< … <<<` block (restored verbatim in `#99`)
- `zsh/zshrc` — the hand-managed optional integrations directly above it (gcloud, openclaw, bun) — *these* correctly use the one-line idiom

## Verification

After restoring Otty's verbatim block (#99): a fresh shell launched, `git status` stayed **clean**,
and `grep -c "otty shell integration >>>" zsh/zshrc` returned **1** (no duplicate). Contrast with
the conformed state (#97), where Otty re-added a second block within one session.
