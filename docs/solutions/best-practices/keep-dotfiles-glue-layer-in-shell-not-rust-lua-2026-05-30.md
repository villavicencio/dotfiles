---
module: dotfiles
date: 2026-05-30
problem_type: best_practice
component: tooling
severity: Low
applies_when:
  - "Considering whether to 'port the dotfiles to Lua and/or Rust' to ride the modern-tooling trend"
  - "Tempted to rewrite the install pipeline (Dotbot + `helpers/*.sh`) in Rust/Go for speed or type-safety"
  - "Tempted to rewrite the Claude Code statusline (`claude/statusline-command.sh`) or hooks as a compiled binary"
  - "Evaluating a shell switch to Nushell for structured-data pipelines"
  - "Deciding where a new piece of config or glue should live (which language/substrate)"
---

# Keep the dotfiles glue layer in shell — adopt Rust *tools*, not Rust *rewrites*

## Decision

"Porting dotfiles to Lua/Rust" is the wrong frame. A dotfiles repo is **layers**, and each
layer wants a different substrate. Match the language to the layer:

| Layer | Substrate | Rationale |
|---|---|---|
| Editor config | **Lua** (nvim — already done, 18 `.lua` files) | The app's config language *is* Lua. |
| CLI tools | **Rust binaries** (have: starship, ripgrep, fd, bat) | Adopt as drop-in replacements via alias/`eval`. |
| Interactive shell | **zsh** (tuned <300ms, lazy loaders) | A shell config configures a shell; not portable to Lua. |
| Install / glue | **bash + Dotbot** (`helpers/*.sh`) | Must run on a bare machine with zero build step. |
| Statusline / hooks | **POSIX `sh`** (dash-safe) | Portability is the whole point (see Axiom history). |

**Do:** adopt more Rust *tools* where they earn it (zoxide, eza, delta, atuin — tracked in
issues #81/#82). That is the only sense of "port to Rust" that pays off: replacing tools, not
rewriting config.

**Don't:** rewrite the install layer, statusline, or hooks in Rust; don't try to write zsh
config "in Lua."

## Why the glue/environment layer stays shell

- **Bootstrap dependency (the decisive argument).** A Rust installer creates a chicken-and-egg
  problem: you'd need `cargo`/`rustc` present *before* you can install your dotfiles. Bash is on
  every machine out of the box. The bootstrap layer must have the fewest possible dependencies.
- **Zero build step.** Shell scripts run as-is. A compiled statusline/installer means per-arch
  binaries and a build/release step to replace a handful of lines.
- **Portability is already a deliberate investment.** The statusline was specifically made
  `dash`-safe (octal escapes, BEL-terminated OSC 8) for the Linux/Axiom target, and `./install`
  has mutation-free `--dry-run`. A compiled rewrite throws that away for no gain.
- **`core.pager = vim -` and friends are intentional.** Tool-config choices in this repo are
  deliberate; "modernize for its own sake" is not a reason to churn them.

## "Lua/structured shell" = switching shells, not porting

You cannot write a shell's interactive config in Lua — the only way to get structured/typed
pipelines is to **switch shells to Nushell** (itself Rust-based). That is a *migration*, not a
port: every `| grep`/`| awk` reflex changes, you lose the zsh plugin ecosystem and the
lazy-loader startup tuning, and work-machine muscle memory fights you. Only worth it if
structured data is the actual goal — not aesthetics.

## See also

- Issues #81 (adopt zoxide + eza), #82 (evaluate delta + atuin) — the actionable adoptions.
- `CLAUDE.md` → "Things intentionally left as-is" (`core.pager = vim -`) and the lazy-loader /
  <300ms startup conventions, which this decision protects.
