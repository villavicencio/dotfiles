# /ticket — Create a GitHub Issue on the Dataworks Website Kanban Board

Use this command to capture any idea, fix, change, or pixel-perfect observation as a properly structured GitHub issue and add it to the project board.

## Repo & Board
- **Repo:** `villavicencio/dataworks-website`
- **Board:** https://github.com/users/villavicencio/projects/1
- **Project ID:** `PVT_kwHOAA0r6c4BRJW-`

## Labels Available
| Label | Use for |
|-------|---------|
| `pixel-perfect` | Visual fidelity vs Figma — spacing, sizing, colors, shadows |
| `bug` | Something broken, incorrect, or missing |
| `content` | Copy or JSON content changes |
| `assets` | Images, icons, logos, SVGs |
| `responsive` | Mobile/tablet layout issues (375px, 768px) |
| `phase-2` | Post-MVP, not urgent, save for later |

## Workflow

### Step 1 — Understand the request
Read the user's description carefully. If a screenshot or image is provided in the conversation, analyze it and extract:
- What page/section it shows
- What the current state looks like
- What needs to change (and why, if visible)

### Step 2 — Compose the issue
Write a well-structured issue with:

```
Title: [Short, action-oriented. Start with a verb. E.g. "Fix hero gradient angle on homepage"]

Body:
## Context
[What prompted this. Reference the Figma export, screenshot, or observation. If an image was provided, describe what it shows and what's wrong.]

## Screenshot / Reference
[If an image was shared, note: "Screenshot provided by David — [describe what it shows]."
If a Figma node is known, reference it: `docs/design/homepage.png` or Figma node `XXX:YYY`.]

## Task
[Numbered steps. Be specific. Reference file paths, component names, JSON keys, Tailwind classes where known.]

## Acceptance
[Clear, testable done criteria. What does "correct" look like?]
```

### Step 3 — Pick labels
Choose 1–3 labels from the table above that best describe the issue. When in doubt: `pixel-perfect` for visual work, `bug` for broken behavior, `phase-2` for non-urgent ideas.

### Step 4 — Create the issue
```bash
export PATH="/Users/dvillavicencio/.config/nvm/versions/node/v24.13.0/bin:$PATH"

ISSUE_URL=$(gh issue create \
  --repo villavicencio/dataworks-website \
  --title "<title>" \
  --label "<label1>,<label2>" \
  --body "<body>")

echo "Created: $ISSUE_URL"
```

### Step 5 — Add to the Kanban board
Get the issue node ID and add it to the project:
```bash
ISSUE_NUMBER=$(echo "$ISSUE_URL" | grep -o '[0-9]*$')
ISSUE_ID=$(gh api repos/villavicencio/dataworks-website/issues/$ISSUE_NUMBER --jq '.node_id')

gh api graphql -f query='
mutation($projectId: ID!, $contentId: ID!) {
  addProjectV2ItemById(input: { projectId: $projectId, contentId: $contentId }) {
    item { id }
  }
}' -f projectId="PVT_kwHOAA0r6c4BRJW-" -f contentId="$ISSUE_ID"

echo "Added to board ✅"
```

### Step 6 — Confirm
Reply with:
- Issue title
- Issue URL
- Labels applied
- One-line summary of what was captured

## Media Handling

If David shares a **screenshot or image**:
1. Analyze it — identify the page, section, and what looks off vs. the Figma design
2. Use your visual analysis as the source of truth for the issue body
3. In the "Screenshot / Reference" section, describe what the image shows
4. Note: "Screenshot attached — [brief description of what it shows]" so the issue body is self-contained even without the image

If a **file path** is given (e.g. a local PNG):
- Read the file with the appropriate tool and analyze it
- Treat the same as an inline screenshot

## Figma Reference
- **File:** https://www.figma.com/design/7GNZYIdywyxuN849dWHbZW/DW2.0-MVP-Website-UX
- **File key:** `7GNZYIdywyxuN849dWHbZW`
- **Known nodes:** CTA Banner `286:926`, Integration `201:3373`

Include the relevant Figma URL or node ID in the ticket body when referencing a specific design section.

## Tips
- One issue per distinct problem — don't bundle unrelated fixes
- Be specific about file paths: `components/Hero.tsx`, `content/home.json`, `app/platform/page.tsx`
- Reference the scale factor when relevant: Figma px × 1.35 = target CSS value
- If the fix is obvious and small (< 5 min), note it in the body so the next CC session can blitz through it
- `phase-2` label = don't block on it, but don't forget it
