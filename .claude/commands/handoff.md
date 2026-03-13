# /handoff — Dotfiles Session Handoff

Use at the end of any dotfiles session to write `HANDOFF.md` at the repo root.
Captures what changed, why, and what's next — so the next session picks up instantly.

Optionally scope it: `/handoff claude commands` or `/handoff nvim config`.

## Steps

### Step 1 — Gather context

```bash
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||' || echo "master")

echo "=== Recent commits ==="
git log --oneline -10

echo "=== Uncommitted changes ==="
git status --short

echo "=== Recently modified files (last session) ==="
git diff --name-only HEAD 2>/dev/null
git ls-files --others --exclude-standard

echo "=== Symlink changes (install.conf.yaml diff) ==="
git diff HEAD -- install.conf.yaml 2>/dev/null || echo "(no changes to install.conf.yaml)"

echo "=== Broken symlinks (if any) ==="
find ~ -maxdepth 4 -type l ! -exec test -e {} \; -print 2>/dev/null | grep -v "Library\|node_modules" | head -20
```

### Step 2 — Write HANDOFF.md

```markdown
# HANDOFF — [YYYY-MM-DD, time of day]

## What Changed
[Concrete bullet list — which config files, which symlinks, which tools.
"Updated nvim/lua/custom/mappings.lua — added telescope live_grep binding" is good.
"Updated nvim config" is not.]

## Why
[The reasoning behind each change. What was broken, what was annoying, what prompted it.
This is the context that's hardest to reconstruct later.]

## install.conf.yaml
[Note any new symlinks added or removed. If nothing changed, say so explicitly.]

## What's Next
[Prioritized. Lead with the single most important thing.
Include any tools you evaluated but didn't finish setting up.]

## Gotchas & Watch-outs
[Anything fragile, any workaround in place, anything to test on a fresh machine.
If a symlink was tricky to get right, document it here.]
```

### Step 3 — Check for issues
Before confirming, flag:
- Any broken symlinks found in Step 1
- Uncommitted changes that should be stashed or committed
- Any tool install that's half-done

### Step 4 — Confirm
Reply with:
- "✅ HANDOFF.md written."
- A 2-sentence summary: what changed and what's next
- "⚠️ Before next session: [thing]" if there's a blocker

## Notes
- Overwrites existing HANDOFF.md — always current state, not a history log
- Commits automatically if slate is clean:
  ```bash
  git add HANDOFF.md && git commit -m "docs: update handoff"
  git remote | grep -q . && git push || echo "(no remote — skipping push)"
  ```
  If there are other uncommitted changes, skip the commit and note it.
- Pairs with `/pickup`
