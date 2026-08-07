---
title: "Otty config cannot be Dotbot-symlinked — `otty config set` atomic-renames over the path"
date: 2026-08-07
category: integration-issues
module: otty
problem_type: integration_issue
component: tooling
symptoms:
  - "A symlink at `~/.config/otty/config.toml` -> repo silently becomes a regular file after the first settings change"
  - "Repo copy of the Otty config stops receiving updates with no error, warning, or git status signal"
  - "`otty config set --config-file <symlink>` reports success and prints the new value, but the link target is never written"
root_cause: design_limitation
resolution_type: workaround
severity: Medium
related_components:
  - development_workflow
  - dotbot
tags:
  - otty
  - dotbot
  - symlink
  - atomic-rename
  - terminal
---

# Otty config cannot be Dotbot-symlinked

## Problem

The obvious way to track `~/.config/otty/config.toml` in this repo is the way every
other config here is tracked: a `link:` entry in `dotbot-conf/`. That approach is
actively unsafe for Otty, and it fails **silently**.

`otty config set` (and, by the same writer, the Settings UI) does not edit the config
file in place. It writes a temp file and `rename(2)`s it over the destination path.
`rename` replaces the *directory entry*, so a symlink sitting at that path is not
followed — it is destroyed and replaced by a regular file.

## Reproduction (otty 1.3.1)

```bash
mkdir -p /tmp/ottytest/real
printf 'copy-on-select = true\n' > /tmp/ottytest/real/config.toml
ln -sfn /tmp/ottytest/real/config.toml /tmp/ottytest/link.toml

otty config set --config-file /tmp/ottytest/link.toml cursor-animation smooth
# prints: cursor-animation = smooth   (exit 0 — looks like success)

ls -la /tmp/ottytest/link.toml        # now a REGULAR FILE, not a symlink
cat  /tmp/ottytest/real/config.toml   # still only copy-on-select — never written
```

The command reports success and prints the value it "set." Nothing indicates the link
was replaced or that the intended target was skipped.

## Why this is worse than a normal breakage

The failure has no observable signal at the moment it happens:

- The CLI exits 0 and echoes the new setting.
- Otty behaves correctly — the live config *is* updated, just at the wrong inode.
- `git status` in the repo is clean, because the repo file genuinely did not change.
- The divergence only surfaces on the next fresh-machine install, when the stale repo
  copy overwrites months of accumulated settings.

This is the same hazard class as the note in `CLAUDE.md` about never symlinking the
repo's `claude/settings.json` over the live `~/.claude/settings.json`.

## Resolution

Seed by **copy**, never link, and add drift reporting so the copy cannot rot unnoticed.

- `helpers/install_otty.sh` copies `otty/config.toml` and
  `otty/themes/com-googlecode-iterm2.ottytheme` into `~/.config/otty/` **only when
  absent**. It never clobbers a live config. macOS-only, dry-run guarded.
- Wired into `dotbot-conf/darwin.yaml` as a `shell:` step rather than a `link:` entry.
- `helpers/report_drift.sh` (`dot drift`) grew an Otty section comparing live against
  tracked, so the seeded copy gets the same drift visibility as `brew/Brewfile` and
  `npm/npm-requirements.txt`.

## Compare normalized forms, not raw files

Otty never rewrites its config cleanly — it *appends*, commenting out superseded values
as `# key = value (reset to default)`. After a few weeks the live file carries ~20 lines
of that tail. A raw `diff` against the repo copy is therefore almost entirely
non-differences.

`otty config show` emits the normalized, section-grouped form. Two properties were
verified before relying on it for drift:

- **Lossless** — every key present in the raw live file appears in `config show` output
  (checked by `comm` over the two key sets; zero keys dropped).
- **Read-only** — running `otty config show --config-file <path>` leaves the file's
  SHA-1 unchanged, so it is safe inside the strictly read-only `report_drift.sh`.

Both sides of the comparison are passed through `otty config show --config-file`, and the
tracked `otty/config.toml` is itself generated from that output.

## Tracking boundary

`~/.config/otty/` holds four things. Only two are worth tracking:

| Path | Tracked | Why |
|---|---|---|
| `config.toml` | **yes** | The actual settings: theme, full custom palette, `copy-on-select`, `macos-option-as-alt`, `font-ligatures`, cursor animation |
| `themes/com-googlecode-iterm2.ottytheme` | **yes** | User-authored — imported from iTerm2 on 2026-07-14 and irreplaceable. It is the active `theme` |
| `themes/*.ottytheme` (24 others) | no | App-seeded reference themes (nord, dracula, tokyo-night, …), all stamped within the same second on first run. Otty regenerates them |
| `fonts/`, `recipes/` | no | `fonts/` holds only an app-generated README (no user fonts installed); `recipes/` is empty apart from a `.migrated-from-statedb` marker |

The mtime spread is what separates authored from seeded: the 24 reference themes all
carry `Jul 13 17:46:53`, while the iTerm2 import carries `17:48:50`.

## Gotcha: `--transient` does not work

`otty config set --transient` is advertised in `--help` but returns
`error: Transient config not yet implemented`. There is no way to preview a config
change without persisting it. Back up `~/.config/otty/config.toml` before any
experiment.
