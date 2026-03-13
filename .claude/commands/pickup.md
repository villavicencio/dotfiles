# /pickup — Pick Up Where We Left Off (Dotfiles)

Use at the start of any dotfiles session to get oriented fast.
Reads HANDOFF.md and tells you exactly where to start.

## Steps

### Step 1 — Read the handoff

```bash
cat HANDOFF.md 2>/dev/null || echo "No HANDOFF.md found."
```

If no HANDOFF.md, fall back:
```bash
git log --oneline -10
git status --short
```

### Step 2 — Load supporting context

```bash
echo "=== Uncommitted changes ==="
git status --short

echo "=== Current branch ==="
git branch --show-current

echo "=== Broken symlinks (quick check) ==="
find ~ -maxdepth 4 -type l ! -exec test -e {} \; -print 2>/dev/null | grep -v "Library\|node_modules" | head -20
```

### Step 3 — Orient and propose next action

1. **2-3 sentence summary** — what was changed last session, what's in flight
2. **"Next up:"** — the single most important thing based on the handoff
3. **Broken symlinks** — if any were found, surface them immediately (they're blocking)
4. **Gotchas to keep in mind** — surface watch-outs before touching anything

Keep it direct. Goal: oriented and working within 60 seconds.

## Notes
- Flag stale handoffs: "This handoff is from X days ago — things may have moved."
- Broken symlinks always surface first — they're the most common dotfiles gotcha
- Don't load tool-specific docs unless the handoff references them
