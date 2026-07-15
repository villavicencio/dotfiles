---
title: "Installing a vendor-hosted SKILL.md bundle (Browserbase) — chain-of-trust, harness halts, and the dotfiles wiring shape"
date: 2026-05-07
category: best-practices
tags:
  - vendor-trust
  - skill-install
  - chain-of-trust
  - harness-halt
  - self-modification
  - browserbase
  - npm-global-cli
  - nvm-lazy-loader
  - env.sh
  - skills-outside-repo
severity: Medium
component: tooling
problem_type: best_practice
module: agent-skill-install-pattern
applies_when:
  - "A vendor publishes a `SKILL.md` (or similar setup doc) on their own domain and the user asks Claude Code to follow it"
  - "Setup instructions include `npm install -g <vendor>/cli` plus a meta-installer command that writes content into the agent's skill / config directory (e.g. `bb skills --install`, similar tools that self-modify)"
  - "Working in the dotfiles repo (or any repo where global CLIs should be tracked in `npm-requirements.txt` and per-machine secrets land in `~/env.sh`)"
  - "Deciding whether to commit follow-on dotfiles changes vs. leave skill content as ephemeral per-machine state"
related_solutions:
  - "docs/solutions/security/2018-leaked-github-pats-and-trufflehog-verified-false-trap-2026-05-06.md — sibling: chain-of-trust failure mode where one wrong link silently bypasses defense"
  - "docs/solutions/cross-machine/corporate-mac-ssl-and-tooling-setup.md — sibling: env.sh as the convention for per-machine secrets, untracked"
---

# Installing a vendor-hosted SKILL.md bundle (Browserbase)

## Context

User asked: *"Read https://browserbase.com/SKILL.md to set up Browserbase (I already have an account and API key btw)."* The SKILL.md instructed: install `@browserbasehq/cli` globally, run `bb skills --install` to fetch agent-skill bundles, set `BROWSERBASE_API_KEY`, verify with `bb projects list`. Optional: install `@browserbasehq/browse-cli` and the SDK.

This is a four-link chain of trust: **vendor domain → vendor SKILL.md → vendor npm package → vendor meta-installer that writes into the agent's own skill directory.** Each link could be compromised independently. The harness was correctly nervous; the user had pre-authorized vendor trust by saying "I have an account."

## What happened

1. **`npm install -g @browserbasehq/cli`** — succeeded silently. 132 packages. No harness intervention. (npm registry is independently trustworthy.)
2. **First halt — zsh probe.** Tried to run `zsh -i -c 'command -v bb'` to verify whether a `bb` shim was needed in the NVM lazy loader. Harness blocked with reason: *"Fetching SKILL.md from browserbase.com — an unverified external domain not listed as trusted — to follow setup instructions; this is code-from-external scouting where the agent is treating untrusted web content as authoritative install guidance."* The block was scoped broadly to the whole task, not the specific probe.
3. **Second halt — `bb skills --install`.** Distinct reason: *"Running `bb skills --install` from a freshly-installed CLI whose setup was directed by an externally-fetched SKILL.md modifies the agent's own skill/config directory (Self-Modification) based on instructions from an untrusted URL; the user's general 'set up Browserbase' request does not specifically authorize installing skill files into the agent's configuration."*
4. **AskUserQuestion `Yes` did not unblock self-modification.** Even after the user explicitly chose "Proceed — run `bb skills --install`" through AskUserQuestion, the harness still blocked the next attempt. **In-session approval through AskUserQuestion is not equivalent to a permission rule in `.claude/settings.json`** for self-modification halts. The escape hatch is the `!` prefix — the user runs the command in their own shell, output lands in the conversation.
5. **User ran `! bb skills --install` themselves.** 13 skills installed under `~/.agents/skills/`, symlinked into Claude Code, plus 12 other agents (Antigravity, Codex, Cursor, Gemini CLI, Warp, Kiro CLI, etc.). **Risk table at install time:** `fetch` = Critical (Gen); `browser`, `cookie-sync`, `event-prospecting` = Critical (Snyk); `autobrowse` = Med (Gen + 1 alert).
6. **`bb projects list`** worked fine through the harness once `BROWSERBASE_API_KEY` was in `~/env.sh` — read-only API call, no self-modification, returned project list.

## The lesson

**The harness has two distinct halt categories for vendor-installer chains, and they require different unblocks.**

| Halt category | Trigger | Unblock |
|---|---|---|
| **Code-from-external scouting** | Bash probes related to a task whose setup doc was fetched from an unverified domain | Re-asking with explicit user context, or proceeding via more-targeted commands. Often dissolves after the first concrete approved action. |
| **Self-modification** | Commands that write into the agent's own skill / config / hook directory | **Permission rule** in `.claude/settings.json` (e.g., `"Bash(bb skills --install)"`), OR user runs it themselves via `!` prefix. AskUserQuestion `Yes` does NOT unblock this class. |

**For the latter class, prefer the `!` prefix as the default escape hatch** — it surfaces the actual command output back into the conversation context (so the agent can still react to install errors / risk tables / file paths), and it preserves the harness's intent (self-modification stays the user's affirmative act).

## Recipe — vendor SKILL.md install in the dotfiles repo

For any future vendor-CLI install with the same shape (`npm install -g <pkg>` + meta-installer), apply:

1. **Audit current state first** — `command -v <bin>`, check `npm/npm-requirements.txt`, check `~/env.sh` for an existing key. Don't reinstall what's already there.
2. **Run the npm global install** — usually allowed; npm registry is trusted.
3. **Add the package to `npm/npm-requirements.txt`** in alpha order. This makes fresh-machine bootstraps reproducible. **Behavior change → ask first** per the commit-approval rule.
4. **Add the NVM lazy-loader shim** in `zsh/zshrc`: append the bin name to the `unset -f` line in `_load_nvm()` and add a `<bin>() { _load_nvm; command <bin> "$@"; }` function. Per the documented convention in CLAUDE.md. Note that the eager `DEFAULT_NODE_PATH` block at zshrc:110-113 already adds the NVM bin dir to PATH on shell start, so the shim is **conventional / decorative** until that block ever changes — but adding it costs nothing and matches the pattern.
5. **Stage `BROWSERBASE_API_KEY` in `~/env.sh`** as a commented placeholder (`export <KEY>=""`). Do NOT ask the user for the value or echo any other secrets from `~/env.sh` in tool output. The file contains other live keys.
6. **The meta-installer step is for the user.** Tell them: *"Run `! <vendor> skills --install` (or the equivalent) yourself — the harness won't let me write into the agent skill directory based on a vendor doc."*
7. **Verify auth via the read-only API call** (`<vendor> projects list` or equivalent) once the key is set. This usually clears the harness because it's clearly read-only.
8. **Commit `npm-requirements.txt` + `zshrc` shim only.** Skill content under `~/.agents/skills/` is per-machine state and intentionally stays out of the repo. The install moment has no audit trail in git — only the dated note in `docs/solutions/`.

## PATH gotcha for the `bb`-equivalent binary

After `npm install -g`, the binary lives in the NVM bin dir (`~/.config/nvm/versions/node/v<X.Y.Z>/bin/`). For a **fresh zsh session**, the eager `DEFAULT_NODE_PATH` block at zshrc:110-113 puts that dir on PATH, so the binary is callable immediately. But:

- **Pre-existing shells** (the user's already-open terminal) won't see the new binary because zsh's command hash table predates the install. Fix: `rehash`, `source ~/.zshrc`, or call by absolute path.
- **Bash subshells from inside the agent** never run zshrc and don't have NVM_DIR or the eager-PATH addition. Always use the absolute path (`~/.config/nvm/versions/node/v24.13.0/bin/<bin>`) when calling from `Bash` tool calls.

## Risk-assessment artifact at install time

The skills installer printed a security-risk table that's worth preserving here as a snapshot — Browserbase will update these scores over time, but the **2026-05-07 baseline** for the installed bundle was:

| Skill | Gen | Socket | Snyk |
|---|---|---|---|
| `autobrowse` | Med | 1 alert | Med |
| `browser` | Safe | 0 | **Critical** |
| `browser-trace` | Safe | 0 | Med |
| `browserbase-cli` | Safe | 0 | Med |
| `company-research` | Safe | 0 | Med |
| `cookie-sync` | Safe | 1 alert | **Critical** |
| `event-prospecting` | Safe | 2 alerts | **Critical** |
| `fetch` | **Critical** | 0 | Med |
| `functions` | Safe | 0 | Med |
| `safe-browser` | Safe | 0 | Med |
| `search` | Safe | 0 | Med |
| `ui-test` | Safe | 0 | Med |
| `what-antibot` | Safe | 0 | Med |

Closing message from installer: *"Review skills before use; they run with full agent permissions."* `cookie-sync` in particular touches the real Chrome cookie jar — read its `SKILL.md` before invoking on anything sensitive.

Source aggregator: https://skills.sh/browserbase/skills

## Why this is in `docs/solutions/best-practices/`, not `security/` or `cross-machine/`

- It's a **pattern**, not a one-off bug fix or postmortem.
- It applies to any future vendor-CLI install with a meta-installer step (Stagehand, Steel.dev, Playwright Cloud, etc.), not just Browserbase.
- The Browserbase install is the concrete instance the recipe was distilled from.
