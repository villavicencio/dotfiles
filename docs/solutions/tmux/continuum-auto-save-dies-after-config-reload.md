---
problem_type: silent plugin state loss
severity: high
module: tmux/continuum
tags: [tmux-continuum, TPM, status-right, config-reload, silent-failure, resurrect]
date_resolved: 2026-04-10
---

# tmux-continuum auto-saves silently die after config reload

## Symptom

9-day gap in `~/.config/tmux/resurrect/` save files (April 1–9, 2026).
No errors, no warnings. Manual `resurrect save` still worked fine.
Auto-saves simply stopped.

## Root Cause

tmux-continuum's auto-save is triggered by a shell command injected into
`status-right` by TPM at server startup. The status bar re-renders every
15 seconds, which invokes the script and checks if the save interval has
elapsed.

`tmux.display.conf` sets `status-right` to a hardcoded value. Any
`tmux source-file` reload overwrites whatever TPM injected, silently
removing the continuum script path. Saves stop, no error is raised.

**Before reload:**
```
status-right "#(/path/to/continuum_save.sh)#[fg=...]│ %H:%M │ %b %d "
```

**After reload:**
```
status-right "#[fg=...]│ %H:%M │ %b %d "
```

## Fix (two layers)

### 1. Inline the continuum script in `status-right`

In `tmux/tmux.display.conf`, embed the script path directly so it can't
be clobbered by reloads:

```tmux
set -g status-right "\
#($XDG_CONFIG_HOME/tmux/plugins/tmux-continuum/scripts/continuum_save.sh)\
#[fg=#4B5263]│ #[fg=#ABB2BF]%H:%M \
#[fg=#4B5263]│ #[fg=#ABB2BF]%b %d "
```

### 2. Belt-and-suspenders: save on every attach

In `tmux/tmux.general.conf`, add a `client-attached` hook that forces a
resurrect save every time a client connects:

```tmux
set-hook -ga client-attached 'run-shell "$XDG_CONFIG_HOME/tmux/plugins/tmux-resurrect/scripts/save.sh"'
```

This covers the edge case where the status-right mechanism itself breaks.

## Verification

1. Reload config: `tmux source-file ~/.config/tmux/tmux.conf`
2. Check: `tmux show-option -g status-right` — must contain `continuum_save.sh`
3. Wait 15+ minutes, check `ls -lt ~/.config/tmux/resurrect/ | head -3`
4. Detach and reattach — a new save should appear immediately

## Prevention

- Never rely solely on TPM runtime injection for values that your config
  file will overwrite on reload.
- If a plugin hooks into `status-right` or `status-left`, inline the hook
  in your own config so it's reload-safe.

## Related

- `docs/solutions/code-quality/claude-code-hook-stdio-detach.md` — similar
  silent-failure pattern with backgrounded subprocesses
