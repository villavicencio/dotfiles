# /reddit — Fetch Reddit Post and Comments

Fetch and summarize a Reddit post with all comments. Takes a URL as argument.

## Steps

### Step 1 — Resolve the URL

If the URL is a short link (contains `/s/`), resolve it first:

```bash
RESOLVED=$(curl -sI "$ARGUMENTS" -L -o /dev/null -w '%{url_effective}')
echo "$RESOLVED"
```

Otherwise use the URL as-is.

### Step 2 — Fetch the post and comments

Append `.json` to the canonical URL and fetch:

```bash
curl -s "${URL}.json?limit=100&depth=5" \
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
  -H "Accept: application/json"
```

### Step 3 — Parse and present

Extract from the JSON:
- **Post**: `data[0].data.children[0].data.selftext` for body, `.title` for title, `.score` for votes
- **Comments**: `data[1].data.children` — recurse `.replies.data.children` for nested replies

Use `jq` to extract. Present as:

1. **Post title and body** — full content, formatted as markdown
2. **Top comments** — sorted by score, include author and score
3. **Key takeaways** — summarize the actionable insights at the end

## Notes
- This works without auth, API keys, or MCP servers
- Always use this approach for Reddit URLs — WebFetch cannot access Reddit
- If the URL returns an error, check that `.json` was appended correctly
