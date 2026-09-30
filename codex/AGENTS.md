# Global instructions — David

Apply across every project. Repo `AGENTS.md` files add to or override these.
Source: dotfiles `codex/AGENTS.md`, linked to `~/.codex/AGENTS.md`. Edit it there, on a branch.
Detailed procedures behind these rules live in `~/Projects/Personal/dotfiles/claude/CLAUDE.md`. Read the named section when a task needs it; don't load it by default.

## Working style
- Lead with the finding or answer. Skip preambles that narrate your next step ("Let me check…"), emphasis that carries no fact ("this is the whole game"), and framing ("The key insight is:"). If deleting a sentence loses nothing I need, delete it.
- On non-trivial decisions, give the reasoning and trade-offs before acting. Raise architectural concerns you notice even when they're outside the task.
- If something is already solved in `docs/solutions/` or the repo's `AGENTS.md`, use it instead of re-deriving it.
- Time: I'm in Pacific time. Label PT vs UTC explicitly, derive weekdays from the system date, and don't call a time "late" or "overnight" without evidence. Sessions are often back-to-back; after `dv:pickup`, measure staleness in commits since the handoff's `head`, not file age.
- Never tell me to sleep, rest, eat, or otherwise manage my time. End cleanly ("standing by") instead.

## Safety
- Never delete user data (files, notes, records, DB rows, board cards) without my explicit approval.
- Never rewrite or force-push shared git history without asking.

## Git
- Changes to runtime behavior, config, or dependencies go on a branch (`feat/`, `fix/`, `chore/`, `docs/`) and merge via PR (or a local merge where a repo has no remote review). Docs, typos, and handoff commits can go straight to the default branch. When in doubt, branch. Stricter repo rules win.

## Code review and merging
- PR review goes through CodeRabbit. Escalate to `dv:gauntlet` for large or risky diffs, for review of something that isn't a PR, or when CodeRabbit is throttled and the review can't wait (`dv:gauntlet report` is the report-only round). Don't hand-roll a review: no `codex exec review` loops, no ad-hoc reviewer panels.
- Batch all fixes, push once, then comment `@coderabbitai review`. A push during an in-flight review aborts it and still burns quota (10 reviews/hour, shared across all my repos and agents; `@coderabbitai rate limit` checks it for free).
- A passing CodeRabbit check doesn't mean a review ran. Read its description: only `Review completed` counts. `rate limited`, `skipped`, and `failed` are all "no review."
  `gh pr checks <N> --json name,state,description -q '.[]|select(.name|test("CodeRabbit";"i"))|"\(.state)\t\(.description)"'`
- Before any merge, list unresolved review threads. Empty output means you can merge; any line blocks. Re-run it after every re-review.
  ```
  gh api graphql -F owner=<o> -F repo=<r> -F pr=<N> -f query='query($owner:String!,$repo:String!,$pr:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$pr){reviewThreads(first:100){nodes{isResolved path line originalLine}}}}}' -q '.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved|not)|"UNRESOLVED \(.path):\(.line // .originalLine)"'
  ```
- Never merge on a stale `CHANGES_REQUESTED`. Fix each finding, or decline it with the reason recorded on the thread and in the PR body. `mergeStateStatus: CLEAN` means nothing is blocking the button, not that the PR was reviewed. If you skip review on a trivial diff, say so when reporting the merge. Merge past a throttled review only for docs/config, with the throttle recorded in the PR body.
- Repos under review should carry `.coderabbit.yaml` with `reviews.auto_review.auto_incremental_review: false`.

## Linear
- Linear is my tracker: workspace `villavicencio`, team key `VIL`, one project per repo or area. Use it on the personal Mac only; never set it up on the work Mac.
- Mark linked issues Done at merge. Mentioning a `VIL-` id in a PR body can auto-close it on merge, so after merging, re-check any ids you named and reopen the ones that aren't finished.
- Put real newlines in Linear markdown, not literal `\n`.

## Current facts
- Versions, model IDs, prices, API endpoints, deprecations, and "as of today" claims are realtime facts, even inside coding work. Don't state them from memory.
- Fetch them: JSON registries and APIs (npm, PyPI, GitHub) directly; everything else through the `browse-gateway` MCP `retrieve` tool (which I call Obscura). Quote only what's on the page, with URL and fetch time, or say you couldn't confirm. Search results are only for finding URLs. Use `dv:cite` when I ask for a verified citation or the claim is high-stakes.
- Reddit: use `dv:reddit`, not a plain fetch.
- The `browserbase` MCP and Browserbase-based skills are retired. Never use them as a fallback. If `browse-gateway` stops resolving, say so; its SSH tunnel is the launchd job `com.dvillavicencio.browse-gateway-tunnel`.

## Durable knowledge
- When you discover a rule, gotcha, or command that works after others failed, write it down in the same turn: the repo's `AGENTS.md` or `docs/solutions/` for project knowledge, or dotfiles for cross-project knowledge. `HANDOFF.md` is overwritten by `dv:handoff`, so it isn't a durable home.
- Before closing a turn that did real work, scan your recap for "next time", "gotcha", or "going forward". Each one either gets written down or is explicitly not a rule.

## Subagents
- Only when I ask, or when an invoked skill's procedure requires them. Invoking the skill is the request, and its independence is the point, so don't simulate the agents in-context. Announce any fan-out of more than 3 agents, or an unbounded batch, before spawning.

## Where the procedures live (sections of dotfiles `claude/CLAUDE.md`)
- Herdr agent fleet, pane template, shims, jump keys: "Herdr fleet & agent building", plus the dotfiles `AGENTS.md`. Herdr changes ride a dotfiles branch.
- Obsidian vaults: "Per-agent Obsidian vaults". Each project owns `~/Obsidian/<name>/`; only `hermes` and `axiom` sync to the VPS.
- Proof docs: "Proof Document Editor". Collaborative docs (plans, specs, memos, drafts) go to Proof via the `proof` skill, titled `Plan: YYYY-MM-DD topic`, `Brainstorm: …`, `Draft: …`, `Reference: …`, `SOUL — <Persona>`. Code-adjacent docs stay in the repo.
- CodeRabbit edge cases and rate-limit mechanics: "Code Review".
