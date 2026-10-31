# Global instructions — David

Apply across every project. Repo `AGENTS.md` files add to or override these.
Source: dotfiles `codex/AGENTS.md`, linked to `~/.codex/AGENTS.md`. Edit it there, on a branch.
Detailed procedures live in dotfiles `docs/agents/` (`~/Projects/Personal/dotfiles/docs/agents/`). Read the named file when a task needs it. Claude Code gets the same rules from `claude/CLAUDE.md`; change both together.

## Working style
- Lead with the finding or answer. Skip preambles that narrate your next step ("Let me check…"), emphasis that carries no fact ("this is the whole game"), and framing ("The key insight is:"). If deleting a sentence loses nothing I need, delete it.
- Keep replies short: I run many sessions and switch between them. Use the same layout every time:
  1. One line: the answer, or where things stand.
  2. **Needs you:** decisions or actions only I can take. Omit if none.
  3. What I need to act or to stay safe: ids, links, blockers, drift, risks. Never cut these for length.
  4. "details?" for the rest.
  Bullets over prose, a table only to compare. Don't restate what I know or what the last reply said. Full detail goes in the handoff, a Linear comment or the PR body, not the chat. One question, at the end.
- Brief me the way a chief of staff briefs a busy executive: I make many decisions a day. Lead with the decision you need and your recommendation, give the context that makes it quick to decide (why it matters, the cost, the risk), have the work ready to approve as is, and be kind.
- On non-trivial decisions, give the reasoning and trade-offs before acting. Raise architectural concerns you notice even when they're outside the task.
- If something is already solved in `docs/solutions/` or the repo's `AGENTS.md`, use it instead of re-deriving it.
- Time: I'm in Pacific time. Label PT vs UTC explicitly, derive weekdays from the system date, and don't call a time "late" or "overnight" without evidence. Sessions are often back-to-back; after `dv:pickup`, measure staleness in commits since the handoff's `head` (validate it first: `session-continuity.md`), not file age.
- Never tell me to sleep, rest, eat, or otherwise manage my time. End cleanly ("standing by") instead.
- Keep sessions small: every turn re-reads the whole context. Hand off and start a fresh session at a seam instead of carrying on: a PR merged, one part of a ticket done, a switch to another ticket, the end of a long detour, or after an hour or more idle. I start the new session, not you: at a seam, end your reply with one line that names it and suggests the handoff, once per seam, not every turn.
- When you name a Linear ticket or a GitHub PR or issue in a reply to me, make it a markdown link that opens in my browser, every time it appears: `[VIL-123](https://linear.app/villavicencio/issue/VIL-123)`, `[#151](https://github.com/<owner>/<repo>/pull/151)` (put the repo in the label for a cross-repo reference, e.g. `[mergewren#31](…)`). Commit messages, PR bodies, and Linear comments can keep bare ids; those surfaces link them already.

## Safety
- Never delete user data (files, notes, records, DB rows, board cards) without my explicit approval. The one standing approval is a merged PR's branch (see Git); it covers nothing else.
- Never rewrite or force-push shared git history without asking.

## Git
- Changes to runtime behavior, config, or dependencies go on a branch (`feat/`, `fix/`, `chore/`, `docs/`) and merge via PR (or a local merge where a repo has no remote review). Docs, typos, and handoff commits can go straight to the default branch. When in doubt, branch. A branch for a Linear ticket puts its id after the type, `<type>/vil-N-<slug>` (e.g. `feat/vil-522-statusline-ticket`), so David's Claude Code statusline can show it. Stricter repo rules win.
- After a PR merges, delete its branch locally and on origin as part of the merge, without asking, using the procedure in `docs/agents/code-review.md` ("After the merge"). It deletes only when the branch holds nothing the merge didn't, and each delete is conditional on the commit it checked. A branch with new commits is kept; say so. A worktree on the branch is cleared first, and only if it's clean. A local merge with no remote deletes the local branch only.
- Parallel sessions on one repo: one worktree and branch per session, never two sessions in one directory. Make it with `wt new <topic> [type]` and remove it after the merge with `wt done <topic>`; the home session (main checkout) owns merges. Details: `docs/agents/parallel-sessions.md`.

## Code review and merging
Repos with their own reviewer follow their own rules: dotfiles and bryancola.com use review-stack (MergeWren), and any repo whose `CLAUDE.md`/`AGENTS.md` names a reviewer as its gate counts. In those repos don't request or wait for CodeRabbit: `@coderabbitai review` there spends the shared quota for nothing, and a CodeRabbit check that appears on its own is informational. (On 2026-10-12 an agent held a bryancola.com merge waiting for CodeRabbit.)
- PR review goes through CodeRabbit. Escalate to `dv:gauntlet` for large or risky diffs, for review of something that isn't a PR, or when CodeRabbit is throttled and the review can't wait (`dv:gauntlet report` is the report-only round). Don't hand-roll a review: no `codex exec review` loops, no ad-hoc reviewer panels.
- Batch all fixes, push once, then comment `@coderabbitai review`. A push during an in-flight review aborts it and still burns quota. The quota is per developer, shared across all my repos and agents, and small (free plan since 2026-09-24: 1 review/hour, and repos under 10 stars get no automatic review, so request each round). `@coderabbitai rate limit` checks what's left without spending a review.
- A passing CodeRabbit check doesn't mean a review ran. Read its description: only `Review completed` counts. `rate limited`, `skipped`, and `failed` are all "no review."
  `gh pr checks <N> --json name,state,description -q '.[]|select(.name|test("CodeRabbit";"i"))|"\(.state)\t\(.description)"'`
- Before any merge, list unresolved review threads (`--paginate` walks every page). Empty output means you can merge; any line blocks. Re-run it after every re-review.
  ```
  gh api graphql --paginate -F owner=<o> -F repo=<r> -F pr=<N> -f query='query($owner:String!,$repo:String!,$pr:Int!,$endCursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$pr){reviewThreads(first:100,after:$endCursor){pageInfo{hasNextPage endCursor}nodes{isResolved path line originalLine}}}}}' -q '.data.repository.pullRequest.reviewThreads.nodes[]|select(.isResolved|not)|"UNRESOLVED \(.path):\(.line // .originalLine)"'
  ```
- Never merge on a stale `CHANGES_REQUESTED`. Fix each finding, or decline it with the reason recorded on the thread and in the PR body. `mergeStateStatus: CLEAN` means nothing is blocking the button, not that the PR was reviewed. If you skip review on a trivial diff, say so when reporting the merge. Merge past a throttled review only for docs/config, with the throttle recorded in the PR body.
- Repos under review should carry `.coderabbit.yaml` with `reviews.auto_review.auto_incremental_review: false`.
- GitHub's closing keywords (`close`, `fix`, `resolve` and their variants, followed by `#N`) work in ordinary sentences. GitHub reads them in a PR's description when the PR targets the default branch, and separately in any commit message that lands on the default branch. The title alone doesn't count, but a squash merge makes it the commit message, which does. "Close #41 unmerged" in skills#48's description closed PR #41 when #48 merged, and left no comment (2026-10-22). Unless you want that, write "PR 41 gets closed". This is the GitHub counterpart of the `VIL-` rule under Linear.

## Linear
- Linear is my tracker: workspace `villavicencio`, team key `VIL`, one project per repo or area. Use it on the personal Mac only; never set it up on the work Mac.
- Mark linked issues Done at merge. Mentioning a `VIL-` id in a PR title or body can auto-close it on merge, even in "VIL-411 filed" (mergewren#62, 2026-10-22). After merging, re-check every id the PR named and reopen the ones that aren't finished. A branch named after a ticket (`feat/vil-391-…`) can close it the same way when its PR merges, so a multi-part ticket gets reopened after the first part.
- Put real newlines in Linear markdown, not literal `\n`.

## Current facts
- Versions, model IDs, prices, API endpoints, deprecations, and "as of today" claims are realtime facts, even inside coding work. Don't state them from memory.
- Fetch them: JSON registries and APIs (npm, PyPI, GitHub) directly; everything else through the `browse-gateway` MCP `retrieve` tool (which I call Obscura). Quote only what's on the page, with URL and fetch time, or say you couldn't confirm. Search results are only for finding URLs. Use `dv:cite` when I ask for a verified citation or the claim is high-stakes.
- Reddit: use `dv:reddit`, not a plain fetch.
- Browserbase is retired and removed. Don't reinstall or suggest it. `browse-gateway` exists on the personal Mac only (SSH tunnel, launchd job `com.dvillavicencio.browse-gateway-tunnel`); where it isn't available or stops resolving, say so and fetch the primary source directly with the same URL-and-fetch-time rule.

## Durable knowledge
- When you discover a rule, gotcha, or command that works after others failed, write it down in the same turn: the repo's `AGENTS.md` or `docs/solutions/` for project knowledge, or dotfiles for cross-project knowledge. `HANDOFF.md` is overwritten by `dv:handoff`, so it isn't a durable home.
- Before closing a turn that did real work, scan your recap for "next time", "gotcha", or "going forward". Each one either gets written down or is explicitly not a rule.

## Subagents
- Only when I ask, or when an invoked skill's procedure requires them. Invoking the skill is the request, and its independence is the point, so don't simulate the agents in-context. Announce any fan-out of more than 3 agents, or an unbounded batch, before spawning.

## Where the procedures live (dotfiles `docs/agents/`)
- CodeRabbit check descriptions, rate-limit mechanics, `.coderabbit.yaml`, deleting a merged branch: `code-review.md`.
- Full web tool ladder (written with Claude Code's tool names): `web-research.md`.
- Handoff `head` validation after `dv:pickup`: `session-continuity.md`.
- Parallel sessions, worktrees, `wt`: `parallel-sessions.md`.
- Secrets via `op-agent` (1Password Agents vault; never print a value or the token file): `1password.md`.
- Obsidian vaults: `obsidian-vaults.md`. Each project owns `~/Obsidian/<name>/`; only `hermes` and `axiom` sync to the VPS.
- Proof docs: `proof.md`. Collaborative docs (plans, specs, memos, drafts) go to Proof via the `proof` skill, titled `Plan: YYYY-MM-DD topic`, `Brainstorm: …`, `Draft: …`, `Reference: …`, `SOUL — <Persona>`. Code-adjacent docs stay in the repo.
- Orca projects (herdr retired 2026-10-22): a new project gets an Orca project (`orca repo add --path <dir>`), a vault, and a project `CLAUDE.md`; worktree setup goes in the repo's `orca.yaml`. Gotchas: dotfiles `docs/reference/orca-worktrees.md`.
