# /ticket — Create a GitHub Issue on the Dotfiles Kanban Board

Use this command to capture bugs, improvements, cross-machine issues, or refactoring tasks as properly structured GitHub issues and add them to the project board.

## Repo & Board
- **Repo:** `villavicencio/dotfiles`
- **Board:** https://github.com/users/villavicencio/projects/2
- **Project ID:** `PVT_kwHOAA0r6c4BRdxZ`

## Labels Available
| Label | Use for |
|-------|---------|
| `bug` | Something broken, incorrect behavior, or errors on shell startup |
| `enhancement` | New feature, alias, function, or tool integration |
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
- Whether this is a bug, enhancement, or cleanup
- Whether it affects one or both machines (personal/work)

### Step 2 — Compose the issue
Write a well-structured issue with:

```
Title: [Short, action-oriented. Start with a verb. E.g. "Fix duplicate PATH entries in zshenv"]

Body:
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
Choose 1-3 labels from the table above. When in doubt: `zsh` for shell config, `cross-machine` if it affects work Mac parity, `cleanup` for dead code removal.

### Step 4 — Create the issue
```bash
ISSUE_URL=$(gh issue create \
  --repo villavicencio/dotfiles \
  --title "<title>" \
  --label "<label1>,<label2>" \
  --body "<body>")

echo "Created: $ISSUE_URL"
```

### Step 5 — Add to the Kanban board
Get the issue node ID and add it to the project:
```bash
ISSUE_NUMBER=$(echo "$ISSUE_URL" | grep -o '[0-9]*$')
ISSUE_ID=$(gh api repos/villavicencio/dotfiles/issues/$ISSUE_NUMBER --jq '.node_id')

gh api graphql -f query='
mutation($projectId: ID!, $contentId: ID!) {
  addProjectV2ItemById(input: { projectId: $projectId, contentId: $contentId }) {
    item { id }
  }
}' -f projectId="PVT_kwHOAA0r6c4BRdxZ" -f contentId="$ISSUE_ID"

echo "Added to board"
```

### Step 6 — Confirm
Reply with:
- Issue title
- Issue URL
- Labels applied
- One-line summary of what was captured

## Tips
- One issue per distinct problem — don't bundle unrelated fixes
- Reference file paths relative to repo root: `zsh/zshenv`, `zsh/zshrc`, `helpers/install_node.sh`
- Note which machine(s) are affected when relevant (personal, work, or both)
- If the fix is obvious and small (< 5 min), note it in the body so the next session can blitz through it
- Use `$HOME` not `/Users/dvillavicencio/` and `$BREW_PREFIX` not `/opt/homebrew/` per CLAUDE.md conventions
