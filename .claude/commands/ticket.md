# /ticket — Create a Linear Issue in the Dotfiles Project

Use this command to capture bugs, improvements, cross-machine issues, or refactoring tasks as properly structured Linear issues in the Dotfiles project.

## Workspace & Project
- **Workspace:** Villavicencio — https://linear.app/villavicencio
- **Team:** `Villavicencio` (key `VIL`)
- **Project:** `Dotfiles` — https://linear.app/villavicencio/project/dotfiles-74974922348e
- Issue tracking migrated here from the GitHub Projects board on 2026-08-20; the old
  board (https://github.com/users/villavicencio/projects/2) is closed history only —
  never create new GitHub issues.

## Tooling
The Linear MCP tools are deferred — load what you need in ONE ToolSearch call before
creating anything:

```
ToolSearch("select:mcp__linear__save_issue,mcp__linear__list_issue_labels")
```

## Labels Available
Workspace defaults plus repo-specific area labels:

| Label | Use for |
|-------|---------|
| `Bug` | Something broken, incorrect behavior, or errors on shell startup |
| `Feature` | New feature, alias, function, or tool integration |
| `Improvement` | Refinement of something that already works |
| `zsh` | Zsh shell config (zshrc, zshenv, aliases, functions, options) |
| `brew` | Homebrew packages, casks, or Brewfile changes |
| `git-config` | Git configuration (gitconfig, gitignore, gitattributes) |
| `cross-machine` | Affects personal/work Mac parity |
| `performance` | Shell startup time or runtime performance |
| `cleanup` | Dead code, stale paths, duplicates, unused exports |
| `nvim` | Neovim configuration |
| `tmux` | Tmux configuration |

## Workflow

### Step 1 — Understand the request
Read the user's description carefully. Identify:
- Which config files are affected
- Whether this is a bug, feature, or cleanup
- Whether it affects one or both machines (personal/work)

### Step 2 — Compose the issue
Write a well-structured issue with:

```
Title: [Short, action-oriented. Start with a verb. E.g. "Fix duplicate PATH entries in zshenv"]

Description:
## Context
[What prompted this. Reference the specific file, line, or shell behavior.]

## Affected Files
[List the config files involved, e.g. `zsh/zshenv`, `zsh/zshrc`]

## Task
[Numbered steps. Be specific. Reference file paths, line numbers, variable names, and shell behavior.]

## Acceptance
[Clear, testable done criteria. What does "correct" look like? E.g. "Running `echo $PATH | tr ':' '\n' | sort | uniq -d` produces no output."]
```

### Step 3 — Pick labels
Choose 1-3 labels from the table above. When in doubt: `zsh` for shell config,
`cross-machine` if it affects work Mac parity, `cleanup` for dead code removal.

### Step 4 — Create the issue
Call `mcp__linear__save_issue` (no `id` — that would be an update):

- `team`: `"Villavicencio"`
- `project`: `"Dotfiles"`
- `state`: `"Todo"` (actionable now) or `"Backlog"` (someday/needs decision)
- `title` / `description`: from Step 2 — pass real newlines in markdown, not `\n` escapes
- `labels`: from Step 3, e.g. `["Bug", "zsh"]`

### Step 5 — Confirm
Reply with:
- Issue identifier (e.g. `VIL-12`) and title
- Issue URL (from the save_issue result)
- Labels applied
- One-line summary of what was captured

## Tips
- One issue per distinct problem — don't bundle unrelated fixes
- Reference file paths relative to repo root: `zsh/zshenv`, `zsh/zshrc`, `helpers/install_node.sh`
- Note which machine(s) are affected when relevant (personal, work, or both)
- If the fix is obvious and small (< 5 min), note it in the description so the next session can blitz through it
- Use `$HOME` not `/Users/<user>/` and `$BREW_PREFIX` not `/opt/homebrew/` per CLAUDE.md conventions
- When resolving a ticket, set its state to `Done` via `save_issue` (id + `state: "Done"`) as part of the merge workflow
