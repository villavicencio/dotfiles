---
title: "sync-vps.yml dry-run does not preview the effect of pending commits"
date: 2026-04-17
category: cross-machine
tags:
  - github-actions
  - sync-vps
  - dry-run
  - vps
  - deploy
  - documentation-gap
  - workflow-semantics
severity: Low
component: ".github/workflows/sync-vps.yml — Fetch and Install steps"
symptoms:
  - "After merging a commit that adds a new Dotbot symlink, the `sync-vps.yml` dry-run Install step prints only `Would run command echo \"Installation complete!\"` — no `Would create symlink` line for the new entry"
  - "Comparing a local fresh-$HOME Dotbot `--dry-run` against the GH Actions dry-run yields completely different output (local shows every `Would create ...` line, CI shows only the final echo)"
  - "Operator expects dry-run to preview what the new commits will do on the VPS and is confused when no per-symlink diff shows in the Install step log"
problem_type: "documentation-gap / workflow semantic surprise"
module: "cross-machine sync workflow"
related_solutions:
  - "docs/solutions/cross-machine/vps-dotfiles-target.md — the VPS runbook that references this workflow"
  - "docs/solutions/code-quality/dotbot-dry-run-requires-v1-23-or-later.md — Dotbot's own --dry-run contract, upstream of this layer"
---

# sync-vps.yml dry-run does not preview the effect of pending commits

## Symptom

Operator merges a commit that adds a new line to `install-linux.conf.yaml`, e.g.:

```yaml
~/.config/tmux/window-meta.json: tmux/window-meta.linux.json
```

Runs `gh workflow run sync-vps.yml ... -f dry_run=true` expecting to see `Would create symlink ~/.config/tmux/window-meta.json -> ...` in the Install step log. What they actually see:

```
Would run command echo "Installation complete!"
```

Nothing else. No per-symlink preview, no evidence the new commit's addition is being considered at all. Locally, the same Dotbot `--dry-run` against a fresh `$HOME` produces the expected `Would create symlink` line, making the CI absence feel like a workflow bug.

## Root cause — this is by design

`sync-vps.yml` runs `./install --dry-run` against the **VPS's current working-tree HEAD**, not against the new commits on `origin/master`. Two load-bearing design choices make this the correct behavior:

1. **Backing-store safety invariant.** `/root/.dotfiles/*` is the backing store for live symlinks on the VPS. Any `git reset --hard` would immediately change the content behind live configs (tmux, zsh, gitconfig, …). Dry-run MUST NOT mutate the working tree, so the Fetch step stays metadata-only.
2. **Idempotent installer.** Because the working tree isn't reset, Dotbot runs against the pre-pending state. Everything in that state is already installed and idempotent, so the output collapses to just the trailing `echo "Installation complete!"` from the shell block.

The workflow source is explicit about both:

`.github/workflows/sync-vps.yml:60-66` (Fetch step, dry-run branch):

```bash
if [ "${{ inputs.dry_run }}" = "true" ]; then
  # Dry-run MUST NOT mutate the VPS working tree. `/root/.dotfiles/*`
  # is the backing store for live symlinks, so `git reset --hard`
  # would change live config content immediately.
  # Fetch is metadata-only (updates remote refs, leaves working tree alone).
  ssh "root@${{ inputs.host }}" \
    'cd /root/.dotfiles && git fetch origin master'
```

`.github/workflows/sync-vps.yml:90-100` (Install step):

```bash
# On dry-run: runs `./install --dry-run` against the CURRENT VPS
# HEAD (not the new commits). This previews what the installer
# would do given the tree as-is. The "Pending commits" summary
# from the previous step shows what would additionally land on
# a real apply.
DRY=""
if [ "${{ inputs.dry_run }}" = "true" ]; then
  DRY="--dry-run"
fi
ssh "root@${{ inputs.host }}" \
  "cd /root/.dotfiles && ./install $DRY"
```

## Where the actual preview lives

Two other places in the workflow give you what you were expecting:

1. **"Pending commits" in `GITHUB_STEP_SUMMARY`.** The Fetch step (lines 68-80) runs `git log --oneline HEAD..origin/master` after the metadata-only fetch and writes the result to the step summary — the markdown block rendered at the top of the Actions run page. **This is the authoritative "what would apply" preview.** If your new commit is in that list, it will land on a real run.
2. **The full-run (`dry_run=false`) Install step log.** Apply mode resets the tree to `origin/master` first (line 82-83), so the Install step emits the full per-symlink `Would create ...` output — but at that point it's not a preview, it's the actual install.

## Solution

**No workflow change required.** The design is correct — the backing-store safety invariant trumps per-symlink preview. The fix lives in the operator's mental model:

- Treat `sync-vps.yml` dry-run as a **connectivity + installer-sanity probe**, not a diff preview.
- Read "Pending commits" in the step summary to verify the right commit range will apply.
- Accept that the Install step's log in dry-run mode will look idempotent.

If you want a true per-symlink preview of a specific commit's effect before triggering the workflow, run the Dotbot fresh-`$HOME` recipe locally (see `CLAUDE.md:158-164`):

```bash
FAKE=/tmp/dotbot-dryrun-$$; mkdir -p "$FAKE"
DOTFILES_DRY_RUN=1 HOME="$FAKE" ./dotbot/bin/dotbot -d "$PWD" -c install-linux.conf.yaml --dry-run
find "$FAKE" -mindepth 1 | wc -l   # must be 0
rm -rf "$FAKE"
```

That operates on the local (post-commit) tree and does produce every `Would create symlink` line.

## Prevention

- **One-liner in the VPS runbook.** Add a callout to `docs/solutions/cross-machine/vps-dotfiles-target.md` near its sync-workflow section: *"Dry-run's Install step runs against the VPS's current HEAD, not origin/master. Verify the pending commit range via 'Pending commits' in the run's step summary; for per-symlink preview, use the local fresh-HOME recipe."*
- **Comment hint in the workflow.** A one-line reference to this solution doc inside the Install step's comment block in `sync-vps.yml` would save the next operator one round-trip of surprise.

## Reproduction (from 2026-04-17 session)

1. Merged `4fbe178` "feat: seed VPS tmux window glyph metadata" to master. Change includes a new `- link:` entry in `install-linux.conf.yaml` (`~/.config/tmux/window-meta.json: tmux/window-meta.linux.json`).
2. Ran `gh workflow run sync-vps.yml --repo villavicencio/dotfiles -f host=openclaw-prod -f dry_run=true` → run ID `24578115874`.
3. Install step log: one line — `Would run command echo "Installation complete!"`. No `Would create symlink` entry for the new file.
4. "Pending commits" step summary: correctly listed `4fbe178 feat: seed VPS tmux window glyph metadata`. That was the real preview.
5. Re-ran with `-f dry_run=false` → run ID `24578272448`. Install step applied cleanly, emitted the expected `Would create symlink ~/.config/tmux/window-meta.json -> ...` line (in dry-run phrasing even during apply — Dotbot's own output template), and the symlink appeared on the VPS:

```
ssh root@openclaw-prod 'readlink ~/.config/tmux/window-meta.json'
# /root/.dotfiles/tmux/window-meta.linux.json
```

Confirmed: dry-run's silence about the new symlink was working-as-designed, not a bug. Apply run worked end-to-end.
