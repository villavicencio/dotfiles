# Global Claude Code instructions — David

Apply across every project on every machine. Project `CLAUDE.md`/`AGENTS.md` files add to or override these.
Source: dotfiles `claude/CLAUDE.md`, linked to `~/.claude/CLAUDE.md`. Codex gets the same rules from `codex/AGENTS.md`; change both together.
Detailed procedures live in dotfiles `docs/agents/` (`~/Projects/Personal/dotfiles/docs/agents/`). Read the named file when a task needs it.

## Working style
- Lead with the finding or answer. No narrated next steps ("Let me check…"), including around tool calls; a one-line status on a background task is fine. No emphasis that carries no fact ("this is the whole game", "the honest truth is") and no framing ("The key insight is:"). If deleting a sentence loses nothing I need, delete it.
- On non-trivial decisions, give the reasoning and trade-offs before acting. Raise architectural concerns you notice even when they're outside the task.
- If something is already solved in `docs/solutions/` or the project's `CLAUDE.md`/`AGENTS.md`, use it instead of re-deriving it.
- Time: I'm in Pacific time. Label PT vs UTC explicitly, derive weekdays from the system date, and don't call a time "late" or "overnight" without wall-clock evidence. Sessions are often back-to-back: after `dv:pickup`, measure staleness in commits since the handoff's `head` (validate it first: `docs/agents/session-continuity.md`).
- Never tell me to sleep, rest, eat, or otherwise manage my time. End cleanly ("standing by") instead.
- When you name a Linear ticket or a GitHub PR or issue in a reply to me, make it a markdown link that opens in my browser, every time it appears: `[VIL-123](https://linear.app/villavicencio/issue/VIL-123)`, `[#151](https://github.com/<owner>/<repo>/pull/151)` (put the repo in the label for a cross-repo reference, e.g. `[mergewren#31](…)`). Commit messages, PR bodies, and Linear comments can keep bare ids; those surfaces link them already.

## Safety
- Never delete user data (files, notes, records, DB rows, board cards) without my explicit approval, even if it looks out of scope. Asking is cheap; an unauthorized deletion isn't.
- Never rewrite or force-push shared git history without asking.

## Git
- Changes to runtime behavior, config, or dependencies go on a branch (`feat/`, `fix/`, `chore/`, `docs/`) and merge via PR (or a local merge where a repo has no remote review). Docs, typos, and handoff commits can go straight to the default branch. When in doubt, branch. Stricter repo rules win.

## Code review and merging
Full procedure, check-description table, and rate-limit mechanics: `docs/agents/code-review.md`. Repos with their own reviewer (dotfiles uses review-stack) follow their own rules.
- PR review goes through CodeRabbit. Escalate to `dv:gauntlet` for large or risky diffs, for review of something that isn't a PR, or when CodeRabbit is throttled and the review can't wait (`dv:gauntlet report` is the report-only round). Don't hand-roll a review: no `codex exec review`, no Claude↔Codex loops, no ad-hoc reviewer panels.
- Batch all fixes, push once, then comment `@coderabbitai review`. A push during an in-flight review aborts it and still burns quota. The quota is per developer, shared across all repos and agents: free plan since 2026-09-24, 1 review/hour, and repos under 10 stars get no automatic review, so request each round. `@coderabbitai rate limit` checks what's left for free.
- A passing CodeRabbit check doesn't mean a review ran. Only the description `Review completed` counts; `rate limited`, `skipped`, and `failed` are all "no review."
  `gh pr checks <N> --json name,state,description -q '.[]|select(.name|test("CodeRabbit";"i"))|"\(.state)\t\(.description)"'`
- Before any merge, list unresolved review threads. Empty output means you can merge; any line blocks. Re-run it after every re-review.
  ```
  gh api graphql --paginate -F owner=<o> -F repo=<r> -F pr=<N> -f query='query($owner:String!,$repo:String!,$pr:Int!,$endCursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$pr){reviewThreads(first:100,after:$endCursor){pageInfo{hasNextPage endCursor}nodes{isResolved path line originalLine}}}}}' -q '.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved|not)|"UNRESOLVED \(.path):\(.line // .originalLine)"'
  ```
- Never merge on a stale `CHANGES_REQUESTED`. Fix each finding, or decline it with the reason on the thread and in the PR body. `mergeStateStatus: CLEAN` means nothing is blocking the button, not that the PR was reviewed. If you skip review on a trivial diff, say so when reporting the merge. Merge past a throttled review only for docs/config, with the throttle recorded in the PR body.

## Linear
- Linear is my tracker: workspace `villavicencio`, team key `VIL`, one project per repo or area. The `linear` MCP is in `~/.claude.json`; its tools are deferred (load with ToolSearch, e.g. `select:mcp__linear__save_issue`). Personal Mac only; never set it up on the work Mac.
- `save_issue`/`save_project` create or update (pass `id` to update). Mark linked issues Done at merge. Put real newlines in markdown, not literal `\n`. Don't create GitHub issues for repos tracked in Linear.
- Mentioning a `VIL-` id in a PR body can auto-close it on merge, so after merging, re-check any ids you named and reopen the ones that aren't finished.

## Current facts and the web
Full ladder: `docs/agents/web-research.md`.
- Versions, model IDs, prices, API endpoints, deprecations, and "as of today" claims are realtime facts, even inside coding work. Don't state them from memory. For Anthropic model IDs and pricing, load the `claude-api` skill.
- Fetch them: `WebFetch` for static pages and JSON registries/APIs; the `browse-gateway` MCP `retrieve` tool (I call it Obscura; load with `ToolSearch("select:mcp__browse-gateway__retrieve")`) for anything WebFetch can't read and for realtime facts. Quote only what's on the page, with URL and fetch time, or say you couldn't confirm. WebSearch only finds URLs; a snippet isn't a verified fact. Use `dv:cite` when I ask for a verified citation or the claim is high-stakes.
- Obscura is set up on the personal Mac only, over an SSH tunnel (launchd job `com.dvillavicencio.browse-gateway-tunnel`); if its tools stop resolving there, check the tunnel. Where `browse-gateway` isn't available (Windows, WSL, work Mac, or a dead tunnel), say so and use `WebFetch` on the primary source with the same URL-and-fetch-time rule; don't silently drop the freshness requirement.
- Browserbase is retired and removed. Don't reinstall or suggest it.
- Reddit: use `dv:reddit`, never WebFetch.
- When you hit a wall on something unfamiliar, search before saying "I don't know."

## Durable knowledge
- When you discover a rule, gotcha, or command that works after others failed, write it down in the same turn: the project's `CLAUDE.md`/`AGENTS.md` or `docs/solutions/` for project knowledge, dotfiles for cross-project knowledge, memory for my preferences. `HANDOFF.md` is overwritten by `dv:handoff`, so it isn't a durable home.
- Before closing a turn that did real work, scan your recap for "next time", "gotcha", "going forward", or "keep in mind". Each one either gets written down or is explicitly not a rule.

## Documents
- Collaborative docs (plans, specs, memos, drafts) go to Proof via the `proof` skill, titled `Plan: YYYY-MM-DD topic`, `Brainstorm: …`, `Draft: …`, `Reference: …`, `SOUL — <Persona>`. Code-adjacent docs (README, `docs/`, `CLAUDE.md`/`AGENTS.md`, `HANDOFF.md`) stay in the repo. API limits and naming table: `docs/agents/proof.md`.

## Subagents
- Only when I ask, or when an invoked skill's procedure requires them. Invoking the skill is the request. Its subagents exist for independence (`dv:gauntlet`'s fresh-context validators, `dv:critique`'s three lenses), so never simulate them in-context; the output looks the same and is worthless.
- Announce a fan-out of more than about 3 agents, or an unbounded batch, in one line before spawning.

## Mac setup (personal Mac)
- **Obsidian vaults:** each project owns `~/Obsidian/<name>/`; Claude Code project memory is symlinked into the vault's `memory/`. Bootstrap, config template, and sync rules: `docs/agents/obsidian-vaults.md`. Only `hermes` and `axiom` sync to the VPS.
- **Herdr agent fleet:** administer it one way, not per project. Pane template (`claude --continue || claude; exec /bin/zsh -il` in a login shell), remote shims, and jump keys are in the dotfiles `CLAUDE.md` "Herdr" section; herdr changes ride a dotfiles branch, never an edit to `~/.config/herdr/`. A new local project agent also gets a vault, a project `CLAUDE.md`, and a jump key.
