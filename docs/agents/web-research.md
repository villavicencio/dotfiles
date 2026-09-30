# Research and the web tool ladder

<!-- Moved out of claude/CLAUDE.md on 2026-09-30 so it loads on demand instead of in every session. The global CLAUDE.md and codex/AGENTS.md keep the one-line rules and point here. -->

Tool names are Claude Code's (`WebFetch`, `WebSearch`, `ToolSearch`); in Codex use its built-in web search and the same `browse-gateway` MCP.

## Research

When you hit a wall — unfamiliar tool, unknown API, missing docs — always perform a web search
before giving up or saying "I don't know." The WebSearch tool is available and should be your
default fallback for anything outside your training data.

## Web Tool Ladder

Three tiers, in order. Reach for the lowest tier that can actually answer the question.

1. **`WebFetch`** — default. Static HTML, server-rendered pages, doc URLs, READMEs, anything
   `curl` would handle. Free and fast. **Machine-readable JSON/registry endpoints (npm
   registry, GitHub API, crates.io, PyPI, etc.) stay at this tier even for "current
   version" facts** — they return authoritative structured data, so tier 2 buys nothing
   there. Reserve the tier-2 preference for pages that need JS rendering or an
   authenticated/live session state a JSON endpoint can't give you.
2. **Obscura (`browse-gateway` MCP)** — preferred for any fetch where WebFetch isn't sufficient
   *and* for **realtime-fact queries** (prices, stock state, "as of today" claims, current-event
   facts, current external-system configuration, current package versions, anything phrased as
   "today" / "right now" / "current" / "as of this writing"). Real browser, JS rendering, anti-bot
   bypass, residential proxies. The user prefers it over the stricter `dv:cite` contract for
   everyday realtime fetches. **When using it for a realtime-fact query, apply the freshness
   discipline manually:** quote only what is literally in the fetched page, attach source URL +
   fetch timestamp to the quote, or decline with a reason. Same contract as `dv:cite` — just
   enforced by you, not the skill.
   > ⚠️ **Obscura is David's branding. It ships as the MCP server named `browse-gateway`.**
   > Nothing on disk is named "obscura" — no binary, no skill, no config string. Searching for
   > the brand name will wrongly read as "not installed." Load the tools with
   > `ToolSearch("select:mcp__browse-gateway__retrieve")` or `+browse-gateway`.
   >
   > - **`mcp__browse-gateway__retrieve`** — the default. Reads any URL as clean markdown
   >   through a stealth browser that clears Cloudflare / anti-bot / CAPTCHA and rotates a
   >   clean residential IP on hard blocks. `forceProxy: true` routes through the residential
   >   proxy from the first request, for known-hostile hosts. **Prefer this for reading a page.**
   > - **`browser_open` / `browser_navigate` / `browser_snapshot` / `browser_click` /
   >   `browser_type` / `browser_select_option` / `browser_press_key` / `browser_wait_for` /
   >   `browser_take_screenshot` / `browser_close`** — stateful drive session, for *interaction*
   >   only (clicks, forms, multi-step flows). Snapshots are ref-annotated; pass `[ref=…]` as
   >   `target`. A warm logged-in session is pinned to one owner host — open a separate session
   >   per host. `browser_close` is idempotent.
   >
   > **Configured globally as of 2026-08-07** in the root `mcpServers` of `~/.claude.json`, as
   > consumer `mac-global` — available in every project on the personal Mac, and only there. `~/Projects/agents`
   > (consumer `argus`) keeps its own project-scoped entry and identity; that is
   > deliberate, not drift.
   >
   > It reaches the gateway over an SSH tunnel on `127.0.0.1:8080`, held by the launchd job
   > `com.dvillavicencio.browse-gateway-tunnel`. If the tools stop resolving, check that tunnel
   > before assuming the server is down — and say so rather than silently dropping to tier 1.
   >
   > **Obscura has no search API.** It retrieves and drives; it does not return SERPs. For
   > *finding* candidate URLs, WebSearch remains the only path — and a fact lifted from a SERP
   > snippet is still not a verified fact. Fetch the candidate with `retrieve` before quoting it.

   **Browserbase is retired (2026-08-07) and removed from the Mac (2026-09-30)** — do not
   reinstall or suggest it. Obscura replaced it. The `browserbase` MCP entries in
   `~/.claude.json` and `~/.codex/config.toml` and the whole `browserbase/skills` bundle
   (`browser`, `browser-trace`, `fetch`, `search`, `autobrowse`, `company-research`,
   `event-prospecting`, `ui-test`, `safe-browser`, `cookie-sync`, `functions`) were deleted;
   a backup sits in `~/.cache/browserbase-retired-20260930/`. For search, use WebSearch →
   `retrieve` (Obscura has no search API).
3. **`dv:cite`** — strict-contract fallback. Use when the user explicitly asks for a
   verified citation, when a claim is high-stakes (financial, medical, legal, public-record),
   or when you want the skill itself to enforce fetch-fresh + substring-assert + freshness-tag-
   or-decline rather than relying on your own discipline. Also the right tool when a fact came
   from training data and you have specifically not yet fetched a current source for it.

**On a failed primary-source fetch for a realtime fact, escalate (tier 1 → tier 2) or decline —
do not fall back to an untagged secondary source.** A 500/blocked official page means "try the
browser tier, or say you couldn't confirm," not "cite a third-party blog as if it were the source."
Anything you do surface still carries its own source URL + fetch timestamp, per the freshness
discipline above.

**Never quote a realtime fact from training data without a freshness tag.** WebSearch returns
SERP snippets that are stale-by-design and do not satisfy the freshness contract — it is fine
for *finding* candidate URLs but a fact lifted from a search snippet is not a verified fact.
When the user asks for a *specific current fact*, route through tier 2 or tier 3, not WebSearch
alone. **Where Obscura isn't available** (Windows, WSL, the work Mac, or a dead tunnel), say so,
then fetch the primary source with `WebFetch` under the same quote-with-URL-and-timestamp rule, or
decline; `dv:cite` still applies where it's installed.

The ladder is for *realtime fetches*, not general reasoning, code review, design discussion, or
summarization of static reference material — those don't need a fetch at all. When in doubt
about whether a query is realtime, prefer fetching (false-positive fetches are recoverable;
silent confabulations from stale training data are not).

**A coding task does not exempt a realtime fact.** A model ID, package version, API endpoint,
pricing figure, or deprecation status is a realtime fact even when the surrounding work is
writing code — and *especially* when the value is about to be committed, where a wrong one ships
silently and fails later at runtime. "This model is stale, the current one is X" is exactly the
claim that needs grounding, not an incidental code edit. For Anthropic model IDs, pricing, and
capabilities specifically, load the `claude-api` skill — it carries the current tables and its own
never-answer-from-memory rule.
