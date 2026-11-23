# Writing Linear tickets

One format for every Linear ticket in every project (VIL-797, decided with David 2026-11-17). This file is the source. The global `claude/CLAUDE.md` and `codex/AGENTS.md` point here under "Linear", and the `dv:ticket` and `dv:groom` skills read it (see the end of this file).

A ticket is often worked days later by an agent that knows only what the ticket says. A missing reason or a vague "done" costs a round of questions or a wrong result. The format exists to prevent those two failures.

## The format

One core format. Leave out a section that has nothing to say, so a typo ticket is Why plus Done means.

| Section | When | Rule |
|---|---|---|
| Why | Always | One or two sentences: the problem and who it costs. This carries the "so that" of a user story. |
| Scope | When there is more than one step | Numbered list of what changes. |
| Out of scope | When something nearby is deliberately left alone | One line each. |
| Done means | Always | A checklist. Each line is a result that a command or an observation can prove, not an activity ("the check exits 0", not "update the check"). |
| Decisions | When any were made | The decision, who made it, the date. |
| Size | When groomed | Small, medium or large, with the count of repos and PRs, and story points (1, 2, 3, 5, 8 or 13) from the anchor table under "Filing and grooming", also set as the ticket's Linear estimate. |
| Agent notes | When there is detail | Collapsed: paths, findings, what was checked and what was not. |

Rules beside the table:

- **Title.** Starts with a verb and names the outcome: "Fix the backup script exiting 0 when the archive step fails", not "Backup script bug".
- **Done means lines are results, not activities.** "`grep -n "tickets.md" claude/CLAUDE.md` prints one line" can be checked. "Update CLAUDE.md" cannot. If a line can't name a command or an observation, the ticket isn't ready.
- **Given/When/Then** is allowed inside Done means for behavior with a clear trigger (a hook, a CLI command, a review verdict). It is not required.
- **The user-story sentence** ("As a [role], I want [thing], so that [reason]") is optional and never required. It suits a feature with a distinct user. Most tickets here are infrastructure, agent procedure or docs, where the user is David or an agent and the sentence comes out forced. Why already carries the reason.
- **Length.** Ask "is someone going to read what I'm writing?" (magical.pm's Linear issue templates, read 2026-11-17). Write what that reader needs to start and to know when to stop, and cut the rest. Detail that only an agent needs goes under Agent notes.
- **Same term for the same thing.** If the Scope says "the check", Done means says "the check".
- **Checklists.** Write Done means as `- [ ]` lines. Linear rendering them as a checklist in the app is not confirmed; they stay readable as plain text either way.

## Type blocks

The core format covers every ticket. A ticket of one of three types adds a block of sections, placed after Why. There is no separate template per type.

| Type | Adds | What each holds |
|---|---|---|
| Bug | Reproduction, Expected, Actual | The steps or command that show it; what should happen; what happens, with the output. |
| Research | Question, Output expected | The one question to answer; the form of the answer (a recommendation, a comparison table, a prototype, a decision for David). |
| Automation | Trigger, Systems touched, Safety | What starts it; which machines, accounts and services it reads or writes; what it must never do and how a failure is contained. |

A bug's Done means still follows the rule above: usually the Reproduction now gives the Expected result.

## Pull condition

A planned ticket left in Backlog has one line stating the exact condition that makes it ready (a `someday` ticket is the exception, below): "Pull when the VIL-N review lands" or "Pull when David picks a date for the migration". A condition names an event or a decision someone can observe, not "later" or "when there's time".

When the condition names a ticket that is still open, or an open PR attached to one, the waiting ticket also gets Linear's blocked-by relation on that ticket, and the line stays: it names the exact event, and once that event happens (the review lands, the PR merges) the relation is stale and comes off even if that ticket stays open for other work (`dv:groom` removes one whose stated PR has merged); a wait that maps to no ticket (a decision, a PR no ticket tracks) has the line alone, and one whose ticket is Canceled or a Duplicate, whose PR closed without merging or is open while its ticket is closed, or that could be more than one ticket goes to David first. A ticket named only as an example or as background is related, not a blocker.

This is different from the `someday` label (`claude/CLAUDE.md`, Linear). A `someday` ticket is a parked idea that is worth keeping and isn't planned. It has no pull condition, and nobody suggests it as next work. A ticket with a pull condition is planned and is waiting on something named. If a ticket's pull condition can't be written, it is probably a `someday` ticket. Adding or removing the label stays David's call.

## Linking a PR to a ticket without closing it

A PR that only partly finishes a ticket says `Refs VIL-N` in its description. The PR that finishes the ticket says `Fixes VIL-N`. Put the line in the PR description only, not the title: the page says "Magic words in PR comments won't create links."

What Linear's documentation says (https://linear.app/docs/github, fetched 2026-11-17 PT):

- "The closing magic words are: close, closes, closed, closing, fix, fixes, fixed, fixing, resolve, resolves, resolved, resolving, complete, completes, completed, completing, implement, implements, implemented, implementing, linear issue."
- "The non-closing magic words are: ref, refs, references, part of, contributes to, toward, towards."
- "The relation magic words are: relates to, related to." A relation word marks the PR as related, "with no status changes".
- On a non-closing word: "the linked PR or commit will still move the issue through other statuses per your workflow settings, but it will not apply the On PR or commit merge status when the PR or commit merges." So a `Refs` PR can still move the ticket to In Progress when it opens. It won't move it to Done when it merges.
- On several PRs: "The Linear issue status will be updated when the final linked PR moves to the required state from your workflow." With two PRs linked to one ticket, both must merge before the status changes.
- On the branch name: "If your branch name includes a Linear issue ID, Linear will automatically link the pull request to that issue."
- To prevent linking: `skip` or `ignore` before the issue ID in the PR description, for example `Ignore ENG-123`, "will fully unlink the PR and prevent status automation, even if the branch name still includes the issue ID."

What the page doesn't say: whether a branch-name link is a closing or a non-closing relationship, or which one wins when the branch name has the id and the description says `Refs`. Don't assume `Refs` is enough. Our own observation says a bare mention in a PR title or body, or a branch named after a ticket, has closed a ticket when the PR merged (`claude/CLAUDE.md`, Linear; mergewren#62, 2026-10-22). So:

- On a PR that only partly finishes a ticket, write `Refs VIL-N` in the description only. Keep the id out of the title, and don't use any closing word with it, in the PR or its commits: close, fix, resolve, complete or implement, in any form (the closing list above).
- After the merge, read the ticket's state. If it moved to Done and isn't finished, reopen it. This is the existing rule in `claude/CLAUDE.md`; it stays in force because the branch-name case is not settled by the docs.
- If a PR must not touch the ticket at all, the docs say to put `Ignore VIL-N` in the description. That is untested here.
- Keep the `<type>/vil-N-slug` branch name that the global rules ask for. It links the PR to the ticket, which is wanted; the reopen step above covers the case where the link closes it.

## Agent notes

Put detail that only an agent needs in a collapsed section at the end of the description. When writing through the Linear MCP, open it with `+++ Agent notes` and close it with `+++` on its own line (the MCP's own guidance). Linear stores it and returns it on read as `>>> Agent notes … >>>` (observed 2026-11-17), so a script or an agent that edits a ticket should expect `>>>` on the way back and write `+++` on the way in.

```
+++ Agent notes

* Paths, findings, what was checked, what was not.

+++
```

A Linear MCP `append` patch lands after the closing `>>>` marker, outside the collapsed section (seen 2026-11-19). So to change Agent notes, rewrite the whole description, with the `+++` markers.

## Model credit

When a ticket moves to Done, it gets one label from the `model` group, unless a rule below says to add none: the model whose commits in the ticket's merged work changed the most lines. Managers, reviewers and groomers are not credited, and the model of the session doing the marking never counts.

Where to read it: the authoring commits of every merged PR linked to the ticket, not only the one that finishes it. For each PR, `gh pr view <N> --json commits` lists its commits oldest first; leave out merges of the base branch into the PR. This repo squash-merges every PR, so the merged commit holds only copies of the source commits' trailers as body text and can't be relied on.

- To find the PRs: use the PR attachments on the ticket in Linear, or `gh pr list --state merged --search "VIL-<N>" --json number,title`. The search matches the PR's title and body, so read each hit and drop any that names a different ticket (`VIL-85` also matches inside `VIL-852`).
- Also count work with no PR (a direct commit or a local merge): the commits on the default branch whose message names the ticket id, found with `git log --no-merges -i --grep="VIL-<N>"`, leaving out every squash commit of a PR (its subject ends in `(#<PR>)`), since those PRs are counted above. They use the same trailer and counting rules below.
- Put all the commits in one list ordered by committer date, oldest first (`committedDate` in the `gh pr view` output, `%cI` in `git log --format`).

A commit names its model in a `Co-Authored-By:` or `Worker-Model:` trailer, matched without regard to case (GitHub's squash merge writes `Co-authored-by:`). The hal overnight runner writes `Worker-Model:`. A commit with no such trailer names no model, and so does one that names two different models (compared by their labels). The model name is the trailer's value without the `<email>` part.

Count each commit's lines as additions plus deletions: `gh api repos/<owner>/<repo>/commits/<sha> -q .stats.total` gives it, and so does summing `git show --numstat <sha>`. Add the counts per model. This measures churn across the commits, so lines a later commit undoes still count for the model that wrote them. Lines in commits that name no model are credited to nobody.

- The label goes to the model with the most lines. If models tie for the most, it goes to the one whose newest commit comes latest in that order.
- If the lines in commits that name no model are more than the top model's lines, add no label. If no authoring commit names a model, or no model has any lines, add no label either. In each case the Done comment says so and why.

The label is the trailer's model name in lower case, with dashes for spaces and dots: `Claude Sonnet 5.5` becomes `claude-sonnet-5-5`, and `Worker-Model: qwen3.8-27b` becomes `qwen3-8-27b`. If the label doesn't exist yet in the `model` group, create it the first time a ticket needs it.

## Existing tickets

No bulk rewrite. A ticket is brought to the format when it is groomed: someone reads it for work, finds a gap, and fixes the gap. A ticket nobody grooms stays as written.

## Linear issue template

We keep one issue template in Linear's app, so a ticket filed by hand starts from the same sections. This file is the source; the template in Linear is a copy. When the format here changes, update the template to match.

The body is the section headings, each with a one-line hint, and nothing more. Type blocks and Agent notes are not in it; add them by hand when the ticket needs them.

```
## Why
One or two sentences: the problem and who it costs.

## Scope
Numbered list of what changes. Leave out for a one-step ticket.

## Out of scope
Things nearby that this ticket deliberately leaves alone. One line each.

## Done means
- [ ] Each line is a result a command or an observation can prove, not an activity.

## Decisions
What was decided, by whom, on what date.

## Size
Small, medium or large, with the count of repos and PRs, and story points (1, 2, 3, 5, 8 or 13). Fill in when groomed.
```

## Worked example 1: a small bug

Title: Fix the backup script exiting 0 when the archive step fails

```
## Why
`backup.sh` prints "done" and exits 0 even when `tar` fails, so the nightly job reports success with no archive. Whoever restores from it finds nothing.

## Reproduction
1. Make the target directory read-only: `chmod a-w ~/backups`.
2. Run `./backup.sh; echo "exit=$?"`.

## Expected
`tar`'s error is printed and the script exits non-zero.

## Actual
`tar: Cannot open: Permission denied` is printed, then `done`, then `exit=0`.

## Done means
- [ ] With `~/backups` read-only, `./backup.sh; echo "exit=$?"` prints `exit=1` and does not print "done".
- [ ] With `~/backups` writable, `./backup.sh; echo "exit=$?"` prints `exit=0` and the archive exists.

## Size
Small: one repo, one PR. 2 points: a small change with one test.
```

The bug adds Reproduction, Expected and Actual after Why. It has no Scope (one step), no Out of scope and no Decisions (nothing was decided), so it leaves those out.

## Worked example 2: a multi-repo ticket

Title: Show sync errors in the notes CLI by having the sync service report them

```
## Why
When the sync service fails to push a note, the `notes` CLI still prints "synced". Users find out days later that a note never left their machine.

## Scope
1. `notes-sync` (service): add an `errors` field to the `/status` response listing each failed note and its error.
2. `notes-cli`: read that field after every sync and print each error, exiting non-zero if there are any.

## Out of scope
- Retrying failed pushes. Tracked separately.
- A UI for the errors in the web app.

## Done means
- [ ] `curl -s localhost:8080/status | jq .errors` against a service holding a failed note prints a non-empty list.
- [ ] `notes sync; echo "exit=$?"` against that service prints the failed note's name and `exit=1`.
- [ ] `notes sync; echo "exit=$?"` with no failed notes prints `synced` and `exit=0`.
- [ ] With a released `notes-sync` (not a local build) running, the `notes sync` check above still prints `exit=1` for a failed note.

## Decisions
* The service reports errors in `/status`; the CLI doesn't read the service's log file. David, 2026-11-17.
* `notes-sync` merges and releases first, because the CLI needs the new field. David, 2026-11-17.

## Size
Medium: two repos, two PRs. 8 points: the change touches two repos.

+++ Agent notes

* `/status` is built in `notes-sync/src/status.py`; failed pushes are already collected in `PushQueue.failed`, so the change is exposing them, not detecting them.
* Checked: the CLI ignores unknown fields in `/status`, so the service can ship first. Not checked: the web app's use of `/status`.

+++
```

Order of the PRs, with the keyword each uses:

- The `notes-sync` PR finishes only part of the ticket: its description says `Refs VIL-N`.
- The `notes-cli` PR finishes the ticket: its description says `Fixes VIL-N`.

In another repo's PR the id is the same; only the keyword changes. After the first merge, read the ticket and reopen it if it moved to Done.

## Filing and grooming

Two skills from the `dv` plugin (repo `villavicencio/skills`) work in this format. Neither starts the work on a ticket; starting is a separate request.

`dv:ticket <request>` files a ticket. It drafts the ticket, checks the facts the draft states, finds the Linear project and labels that fit, and creates it only after you confirm.

`dv:groom VIL-N` grooms one existing ticket before anyone works it. `dv:ticket groom VIL-N` still works and hands the ticket to `dv:groom`. A run:

1. Reads the ticket, its comments and its neighbors: related, blocking and blocked tickets, the parent and children, and each PR it names. It also searches the team for work that is already done or planned elsewhere.
2. Checks the ticket against this format and lists the gaps.
3. Checks every fact that a Scope step or a Done means line depends on, against the repo commit or the system the fact is about, and samples the rest. It closes a conditional step ("check whether X; if so, do Y") when one or two read-only commands settle it, and turns each prerequisite into a blocked-by relation when it maps to one ticket.
4. Proposes a size, with the count of repos and PRs, and Fibonacci story points, and decides whether to split the ticket. Points measure the effort for whoever works the ticket, not its importance, and are set in Linear's estimate field. The anchor table: 1 = a one-line docs or config change; 2 = a small change with one test; 3 = a change across a few files with tests; 5 = a feature-sized change in one repo; 8 = a change that touches several modules or two repos; 13 = too big to run as one ticket. As a guide and not a rule, small is typically 1–3 points, medium 5, large 8–13. Above 8 it proposes a split, with each child pointed; a 13 is never left unsplit without David's explicit yes.
5. Looks once past the ticket's text for small improvements that belong in it, spin-off tickets (at most three) and process problems, such as a branch name that breaks a repo's rule.
6. Asks every open decision as a multiple-choice interview, at most four questions a round. A numeric target is always David's to set.
7. Applies only the numbered edits David approves, and files only the children and spin-offs David approved. A yes to a split or a spin-off in the interview approves filing it as shown. When it applies a grooming, it adds the `groomed` label to the ticket, so the board shows which tickets are groomed.

**Splits.** A ticket is split when its parts can merge on their own in different repos, when it mixes a mechanical change with a design choice, when part of it is blocked, when it is large or pointed above 8, or when one part is risky. It is not split when the parts must land together. The parent either becomes the first child or stays as the parent with the children under it, in which case its description is replaced by one whose Scope names the children. Linear can't create tickets and edit another in one step, so the children are filed first and the parent is changed last. A failure part way leaves the work in two places, never in none. Groom stops on a create error or when the parent changed since the split was approved, and lists what exists for David to settle.

**Spin-offs.** Work the ticket suggests but should not carry, filed as its own ticket related to the groomed one, after a duplicate search.

**Agent notes.** Groom opens the ticket's Agent notes with a grooming line, `Groomed <date> <time> <zone> against <repo> <commit>`, and adds up to three lists, each only when it has something in it:

- **Checked and current:** each fact it checked, with how.
- **For the engineer:** the repo rules that bite on this ticket, the branch name to use, what not to touch.
- **After the merge:** follow-ups that are not the worker's, such as notes to update or a ticket to comment on.

A ticket written by hand, in the Linear UI or by an agent without these skills, follows this file.
