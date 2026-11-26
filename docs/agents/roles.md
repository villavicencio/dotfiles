# The five agent roles

Who fills each role in the chain of agents, what each decides, and where its decisions and
escalations go (VIL-1036). Skills and docs should point here instead of saying "me", "David", "the
home session", "the worktree session" or "hired agents".

The chain, from the top:

1. **CEO**: David.
2. **Head of a department** ("Head" below): an Orca bot.
3. **Director**: the home session in a repo's main checkout.
4. **Manager**: a ticket's worktree session.
5. **Engineer**: an agent a Manager or Director hires.

Each role decides its own routine calls and hands up what it doesn't decide, to the role above it.
This page sets no authority beyond what the skills and the global instructions already give.

The CEO's 1% is the only thing a Head hands up to the CEO. What it holds, and the rule that sends a
question up the chain, are in the `dv:director-mode` section "Answer a worktree session's question"
(skills repo, `plugins/dv/skills/director-mode/SKILL.md`). That is the one copy; this page keeps
none.

## CEO

- **Fills it:** David.
- **Decides:** the direction, and the CEO's 1%.
- **Hands up:** nothing; this is the top of the chain.
- **Gets from below:** only the CEO's 1%, and only from a Head.

## Head of a department

- **Fills it:** an Orca bot that runs one department for the CEO. The role is "Head of
  <department>", and its lane is one Linear project or a set of them. More than one Head can
  exist. The first is the Head of Skills, on hal, addressed `bot:Head of Skills`. How a Head is
  stood up: `docs/reference/orca-bots.md`, "Standing up a Head".
- **Decides:** the routine calls in its lane, for the CEO. Its `SOUL.md` names its lane, the chain
  and what it decides.
- **Hands up:** only the CEO's 1%, to the CEO.
- **Gets from below:** what the routing rule in the `dv:director-mode` section above sends it.

## Director

- **Fills it:** the home session, running in a repo's main checkout on the default branch, with
  `dv:director-mode` on.
- **Decides:** the routine calls for the Manager sessions under it. `dv:director-mode` lists
  them, such as scope cuts and the kinds of delete the global standing approvals cover. It owns
  the things there is only one of: merges (after the reviewer's verdict), the cleanup after each
  merge, and the true state of the tickets (`docs/agents/parallel-sessions.md`, "Roles"). It opens
  a ticket's worktree on request and recommends which sessions to start next.
- **Hands up:** what it doesn't decide, up the chain, under the routing rule in `dv:director-mode`.
- **Does not:** hire engineers for a ticket's work. That belongs to the ticket's Manager. It hires
  only for work that isn't a ticket's own.

## Manager

- **Fills it:** a ticket's worktree session, running `dv:manager-mode`. One per ticket.
- **Decides:** the plan, the briefs, the order of work, and whether an Engineer's report meets the
  brief. It runs MergeWren fix rounds 1 and 2 on its PR. It never writes code.
- **Hands up:** a question goes to the Director first (`dv:manager-mode`, "Questions go to the
  Director first"). A PR that passed MergeWren goes to the Director to merge. A Manager never
  merges.
- **Hires:** the Engineers for its ticket, each on a named model and effort.

## Engineer

- **Fills it:** an agent a Manager or a Director hires for one unit of work (a ticket, a PR, a fix
  round, a review), on a named model and effort. It does the engineering.
- **Decides:** how to do its unit within the brief it was given.
- **Hands up:** one report to whoever hired it. A blocker goes in that report. A deliberate
  barrier, such as a denied permission or a gate, is reported, not routed around.

## MergeWren

In a repo MergeWren (review-stack) covers, it is the PR reviewer. It reviews every new head of an
open, non-draft PR and posts a verdict. It is a gate each such PR passes, not a role that decides.
The Manager fixes or declines its findings, and the Director merges under the rules in
`docs/agents/code-review.md`. That file also says which repos MergeWren covers, what a repo not
yet onboarded or one that names its own reviewer does instead, and how to wait for a verdict
("Merging on a MergeWren review").
